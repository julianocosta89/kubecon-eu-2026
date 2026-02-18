#!/bin/bash
set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE TABLE IF NOT EXISTS songs (
        id BIGSERIAL PRIMARY KEY,
        title VARCHAR(255) NOT NULL,
        artist VARCHAR(255) NOT NULL,
        album VARCHAR(255),
        year INT,
        duration_ms INT,
        genre VARCHAR(255),
        cached_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        CONSTRAINT unique_title_artist UNIQUE (title, artist)
    );

    INSERT INTO songs (title, artist, album, year, duration_ms, genre)
    VALUES ('Polly', 'Nirvana', 'Nevermind', 1991, 151800, 'Rock')
    ON CONFLICT (title, artist) DO NOTHING;
EOSQL
