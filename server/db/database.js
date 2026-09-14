/**
 * db/database.js — SQLite database wrapper for multi-channel-ytl
 *
 * Replaces the db_channels.json file with a proper SQLite database.
 * Provides the same API as the old JSON-based system:
 *   - loadDatabase() → returns a Map of channels (same as before)
 *   - saveDatabase(channelsMap) → writes to SQLite (replaces JSON.stringify)
 *
 * Features:
 *   - Auto-migrates from db_channels.json on first run
 *   - Indexed queries for fast lookups
 *   - Incremental writes (no more "write entire file on every change")
 *   - Keeps db_channels.json as a read-only backup after migration
 */

const Database = require('better-sqlite3');
const path = require('path');
const fs = require('fs');

const DB_PATH = path.join(__dirname, 'database.db');
const LEGACY_JSON_PATH = path.join(__dirname, '..', 'db_channels.json');

let db = null;

/**
 * Initialize the database. Creates tables if they don't exist.
 * Auto-migrates from db_channels.json if the DB file is missing.
 */
function initDatabase() {
    db = new Database(DB_PATH);
    db.pragma('journal_mode = WAL');  // Better concurrent read performance
    db.pragma('foreign_keys = ON');

    // Create tables if they don't exist
    db.exec(`
        CREATE TABLE IF NOT EXISTS channels (
            id TEXT PRIMARY KEY,
            youtubeId TEXT,
            url TEXT,
            name TEXT,
            handle TEXT,
            videoCount INTEGER,
            lastChecked TEXT,
            createdAt TEXT
        );

        CREATE TABLE IF NOT EXISTS videos (
            id TEXT PRIMARY KEY,
            channelId TEXT,
            title TEXT,
            duration INTEGER,
            views INTEGER,
            uploadDate TEXT,
            finalFilename TEXT,
            sanitizedBase TEXT,
            durationSuffix TEXT,
            displayTitle TEXT,
            downloadStatus TEXT,
            syncStatus TEXT,
            filePath TEXT,
            isDuplicate INTEGER DEFAULT 0,
            isLiveStream INTEGER DEFAULT 0,
            isPremiere INTEGER DEFAULT 0,
            FOREIGN KEY (channelId) REFERENCES channels(id) ON DELETE CASCADE
        );

        CREATE INDEX IF NOT EXISTS idx_videos_channelId ON videos(channelId);
        CREATE INDEX IF NOT EXISTS idx_videos_finalFilename ON videos(finalFilename);
        CREATE INDEX IF NOT EXISTS idx_videos_syncStatus ON videos(syncStatus);
        CREATE INDEX IF NOT EXISTS idx_videos_uploadDate ON videos(uploadDate);
    `);

    // Check if we need to migrate from JSON
    const channelCount = db.prepare('SELECT COUNT(*) as count FROM channels').get().count;
    if (channelCount === 0 && fs.existsSync(LEGACY_JSON_PATH)) {
        migrateFromJson();
    }

    console.log(`[Database] SQLite initialized at ${DB_PATH}`);
    const stats = db.prepare(`
        SELECT
            (SELECT COUNT(*) FROM channels) as channels,
            (SELECT COUNT(*) FROM videos) as videos
    `).get();
    console.log(`[Database] Loaded ${stats.channels} channels, ${stats.videos} videos`);
}

/**
 * Migrate data from db_channels.json to SQLite.
 * Runs once on first startup if the DB is empty and JSON exists.
 */
function migrateFromJson() {
    console.log('[Database] 📦 Migrating from db_channels.json to SQLite...');
    const raw = fs.readFileSync(LEGACY_JSON_PATH, 'utf8');
    const channels = JSON.parse(raw);

    if (!Array.isArray(channels)) {
        console.error('[Database] ❌ JSON is not an array, skipping migration');
        return;
    }

    const insertChannel = db.prepare(`
        INSERT OR REPLACE INTO channels (id, youtubeId, url, name, handle, videoCount, lastChecked, createdAt)
        VALUES (@id, @youtubeId, @url, @name, @handle, @videoCount, @lastChecked, @createdAt)
    `);

    const insertVideo = db.prepare(`
        INSERT OR REPLACE INTO videos (id, channelId, title, duration, views, uploadDate, finalFilename, sanitizedBase, durationSuffix, displayTitle, downloadStatus, syncStatus, filePath, isDuplicate, isLiveStream, isPremiere)
        VALUES (@id, @channelId, @title, @duration, @views, @uploadDate, @finalFilename, @sanitizedBase, @durationSuffix, @displayTitle, @downloadStatus, @syncStatus, @filePath, @isDuplicate, @isLiveStream, @isPremiere)
    `);

    let channelCount = 0;
    let videoCount = 0;

    const migrateAll = db.transaction((channels) => {
        for (const ch of channels) {
            if (!ch || !ch.id) continue;

            insertChannel.run({
                id: ch.id,
                youtubeId: ch.youtubeId || null,
                url: ch.url || null,
                name: ch.name || null,
                handle: ch.handle || null,
                videoCount: ch.videoCount || 0,
                lastChecked: ch.lastChecked || null,
                createdAt: ch.createdAt || new Date().toISOString()
            });
            channelCount++;

            const videos = ch.videos || [];
            for (const v of videos) {
                const vidId = v.id || v.videoId || `unknown_${videoCount}`;
                insertVideo.run({
                    id: vidId,
                    channelId: ch.id,
                    title: v.title || null,
                    duration: v.duration || null,
                    views: v.views || null,
                    uploadDate: v.uploadDate || null,
                    finalFilename: v.finalFilename || null,
                    sanitizedBase: v.sanitizedBase || null,
                    durationSuffix: v.durationSuffix || null,
                    displayTitle: v.displayTitle || null,
                    downloadStatus: v.downloadStatus || null,
                    syncStatus: v.syncStatus || null,
                    filePath: v.filePath || null,
                    isDuplicate: v.isDuplicate ? 1 : 0,
                    isLiveStream: v.isLiveStream ? 1 : 0,
                    isPremiere: v.isPremiere ? 1 : 0
                });
                videoCount++;
            }
        }
    });

    migrateAll(channels);

    // Rename the JSON file so it's preserved as a backup but not used anymore
    const backupPath = LEGACY_JSON_PATH + '.migrated';
    try {
        fs.renameSync(LEGACY_JSON_PATH, backupPath);
        console.log(`[Database] ✅ Migration complete: ${channelCount} channels, ${videoCount} videos`);
        console.log(`[Database] 📦 Original JSON backed up to: ${backupPath}`);
    } catch (e) {
        console.warn(`[Database] ⚠️ Could not rename JSON backup: ${e.message}`);
    }
}

/**
 * Load all channels + videos from SQLite into a Map.
 * Same return format as the old JSON system.
 * @returns {Map<string, object>} Map of channelId → channel object
 */
function loadDatabase() {
    if (!db) initDatabase();

    const channels = new Map();

    const channelRows = db.prepare('SELECT * FROM channels').all();
    const videoRows = db.prepare('SELECT * FROM videos').all();

    // Group videos by channelId
    const videosByChannel = new Map();
    for (const vRow of videoRows) {
        if (!videosByChannel.has(vRow.channelId)) {
            videosByChannel.set(vRow.channelId, []);
        }
        videosByChannel.get(vRow.channelId).push({
            id: vRow.id,
            title: vRow.title,
            duration: vRow.duration,
            views: vRow.views,
            uploadDate: vRow.uploadDate,
            finalFilename: vRow.finalFilename,
            sanitizedBase: vRow.sanitizedBase,
            durationSuffix: vRow.durationSuffix,
            displayTitle: vRow.displayTitle,
            downloadStatus: vRow.downloadStatus,
            syncStatus: vRow.syncStatus,
            filePath: vRow.filePath,
            isDuplicate: !!vRow.isDuplicate,
            isLiveStream: !!vRow.isLiveStream,
            isPremiere: !!vRow.isPremiere
        });
    }

    for (const chRow of channelRows) {
        channels.set(chRow.id, {
            id: chRow.id,
            youtubeId: chRow.youtubeId,
            url: chRow.url,
            name: chRow.name,
            handle: chRow.handle,
            videoCount: chRow.videoCount,
            lastChecked: chRow.lastChecked,
            createdAt: chRow.createdAt,
            videos: videosByChannel.get(chRow.id) || []
        });
    }

    return channels;
}

/**
 * Save a single channel (and its videos) to SQLite.
 * Uses INSERT OR REPLACE (upsert) for each row.
 * @param {string} channelId
 * @param {object} channel
 */
function saveChannel(channelId, channel) {
    if (!db) initDatabase();

    const insertChannel = db.prepare(`
        INSERT OR REPLACE INTO channels (id, youtubeId, url, name, handle, videoCount, lastChecked, createdAt)
        VALUES (@id, @youtubeId, @url, @name, @handle, @videoCount, @lastChecked, @createdAt)
    `);

    const insertVideo = db.prepare(`
        INSERT OR REPLACE INTO videos (id, channelId, title, duration, views, uploadDate, finalFilename, sanitizedBase, durationSuffix, displayTitle, downloadStatus, syncStatus, filePath, isDuplicate, isLiveStream, isPremiere)
        VALUES (@id, @channelId, @title, @duration, @views, @uploadDate, @finalFilename, @sanitizedBase, @durationSuffix, @displayTitle, @downloadStatus, @syncStatus, @filePath, @isDuplicate, @isLiveStream, @isPremiere)
    `);

    const saveOne = db.transaction((chId, ch) => {
        insertChannel.run({
            id: chId,
            youtubeId: ch.youtubeId || null,
            url: ch.url || null,
            name: ch.name || null,
            handle: ch.handle || null,
            videoCount: ch.videoCount || (ch.videos ? ch.videos.length : 0),
            lastChecked: ch.lastChecked || null,
            createdAt: ch.createdAt || new Date().toISOString()
        });

        const videos = ch.videos || [];
        for (const v of videos) {
            const vidId = v.id || v.videoId || `unknown_${Math.random()}`;
            insertVideo.run({
                id: vidId,
                channelId: chId,
                title: v.title || null,
                duration: v.duration || null,
                views: v.views || null,
                uploadDate: v.uploadDate || null,
                finalFilename: v.finalFilename || null,
                sanitizedBase: v.sanitizedBase || null,
                durationSuffix: v.durationSuffix || null,
                displayTitle: v.displayTitle || null,
                downloadStatus: v.downloadStatus || null,
                syncStatus: v.syncStatus || null,
                filePath: v.filePath || null,
                isDuplicate: v.isDuplicate ? 1 : 0,
                isLiveStream: v.isLiveStream ? 1 : 0,
                isPremiere: v.isPremiere ? 1 : 0
            });
        }
    });

    saveOne(channelId, channel);
}

/**
 * Save all channels to SQLite (full sync).
 * This is the replacement for the old saveDatabase() that wrote the entire JSON.
 * ⚠️ SLOW: O(channels × videos) per call. Use saveChannel() or saveVideo()
 *    for incremental updates whenever possible.
 * @param {Map<string, object>} channelsMap
 */
function saveAllChannels(channelsMap) {
    if (!db) initDatabase();

    const saveAll = db.transaction(() => {
        for (const [channelId, channel] of channelsMap.entries()) {
            saveChannel(channelId, channel);
        }
    });

    saveAll();
}

/**
 * ⭐ PERF: Save just the channel-level metadata (no videos).
 * Use this when only channel fields like lastChecked / videoCount / name
 * changed — avoids re-inserting every video row.
 * @param {string} channelId
 * @param {object} channel - Channel object (videos array ignored if present)
 */
function saveChannelMetadata(channelId, channel) {
    if (!db) initDatabase();

    const insertChannel = db.prepare(`
        INSERT OR REPLACE INTO channels (id, youtubeId, url, name, handle, videoCount, lastChecked, createdAt)
        VALUES (@id, @youtubeId, @url, @name, @handle, @videoCount, @lastChecked, @createdAt)
    `);

    insertChannel.run({
        id: channelId,
        youtubeId: channel.youtubeId || null,
        url: channel.url || null,
        name: channel.name || null,
        handle: channel.handle || null,
        videoCount: channel.videoCount || (channel.videos ? channel.videos.length : 0),
        lastChecked: channel.lastChecked || null,
        createdAt: channel.createdAt || new Date().toISOString()
    });
}

/**
 * ⭐ PERF: Save/update a single video row.
 * Used when only one video's status/filename changed (the most common case
 * during downloads). O(1) instead of O(channel video count).
 * @param {string} channelId - Parent channel ID
 * @param {object} video - Video object (id required, other fields optional)
 */
function saveVideo(channelId, video) {
    if (!db) initDatabase();

    const vidId = video.id || video.videoId;
    if (!vidId) {
        console.warn('[Database] saveVideo: video has no id, skipping');
        return;
    }

    const insertVideo = db.prepare(`
        INSERT OR REPLACE INTO videos (id, channelId, title, duration, views, uploadDate, finalFilename, sanitizedBase, durationSuffix, displayTitle, downloadStatus, syncStatus, filePath, isDuplicate, isLiveStream, isPremiere)
        VALUES (@id, @channelId, @title, @duration, @views, @uploadDate, @finalFilename, @sanitizedBase, @durationSuffix, @displayTitle, @downloadStatus, @syncStatus, @filePath, @isDuplicate, @isLiveStream, @isPremiere)
    `);

    insertVideo.run({
        id: vidId,
        channelId: channelId,
        title: video.title || null,
        duration: video.duration || null,
        views: video.views || null,
        uploadDate: video.uploadDate || null,
        finalFilename: video.finalFilename || null,
        sanitizedBase: video.sanitizedBase || null,
        durationSuffix: video.durationSuffix || null,
        displayTitle: video.displayTitle || null,
        downloadStatus: video.downloadStatus || null,
        syncStatus: video.syncStatus || null,
        filePath: video.filePath || null,
        isDuplicate: video.isDuplicate ? 1 : 0,
        isLiveStream: video.isLiveStream ? 1 : 0,
        isPremiere: video.isPremiere ? 1 : 0
    });
}

/**
 * ⭐ PERF: Patch a single field on a single video row.
 * Use this for the post-download rename case where only `finalFilename` changed.
 * @param {string} videoId
 * @param {object} patch - {field: value, ...} — only these fields get UPDATEd
 */
function patchVideoFields(videoId, patch) {
    if (!db) initDatabase();
    if (!videoId || !patch || Object.keys(patch).length === 0) return;

    // Whitelist allowed columns to prevent SQL injection
    const ALLOWED = new Set([
        'title', 'duration', 'views', 'uploadDate',
        'finalFilename', 'sanitizedBase', 'durationSuffix', 'displayTitle',
        'downloadStatus', 'syncStatus', 'filePath',
        'isDuplicate', 'isLiveStream', 'isPremiere'
    ]);

    const sets = [];
    const values = {};
    for (const [k, v] of Object.entries(patch)) {
        if (!ALLOWED.has(k)) continue;
        // Map JS boolean → SQLite integer for the is* fields
        const value = (k === 'isDuplicate' || k === 'isLiveStream' || k === 'isPremiere')
            ? (v ? 1 : 0)
            : v;
        sets.push(`${k} = @${k}`);
        values[k] = value;
    }
    if (sets.length === 0) return;

    values.id = videoId;
    db.prepare(`UPDATE videos SET ${sets.join(', ')} WHERE id = @id`).run(values);
}

/**
 * ⭐ PERF: Patch a single field on a channel row (no video rows touched).
 * @param {string} channelId
 * @param {object} patch - {field: value, ...}
 */
function patchChannelFields(channelId, patch) {
    if (!db) initDatabase();
    if (!channelId || !patch || Object.keys(patch).length === 0) return;

    const ALLOWED = new Set([
        'youtubeId', 'url', 'name', 'handle',
        'videoCount', 'lastChecked', 'createdAt'
    ]);

    const sets = [];
    const values = {};
    for (const [k, v] of Object.entries(patch)) {
        if (!ALLOWED.has(k)) continue;
        sets.push(`${k} = @${k}`);
        values[k] = v;
    }
    if (sets.length === 0) return;

    values.id = channelId;
    db.prepare(`UPDATE channels SET ${sets.join(', ')} WHERE id = @id`).run(values);
}

/**
 * Delete a channel and all its videos.
 * @param {string} channelId
 */
function deleteChannel(channelId) {
    if (!db) initDatabase();
    db.prepare('DELETE FROM channels WHERE id = ?').run(channelId);
    db.prepare('DELETE FROM videos WHERE channelId = ?').run(channelId);
}

/**
 * Close the database connection.
 */
function closeDatabase() {
    if (db) {
        db.close();
        db = null;
    }
}

module.exports = {
    initDatabase,
    loadDatabase,
    saveChannel,
    saveAllChannels,
    saveChannelMetadata,
    saveVideo,
    patchVideoFields,
    patchChannelFields,
    deleteChannel,
    closeDatabase,
    getDb: () => db
};
