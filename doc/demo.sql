create table commands (
    id integer primary key autoincrement,
    argv text,
    unique(argv) on conflict ignore
);
create table places (
    id integer primary key autoincrement,
    host text,
    dir text,
    unique(host, dir) on conflict ignore
);
create table history (
    id integer primary key autoincrement,
    session integer,
    command_id integer references commands(id),
    place_id integer references places(id),
    exit_status integer,
    start_time integer,
    duration integer
);
pragma user_version = 2;

insert into commands(id, argv) values
    (1, 'git status --short'),
    (2, 'git log --oneline --decorate -10'),
    (3, 'git diff --stat'),
    (4, 'mise run format:check'),
    (5, 'zsh -f tests/run.zsh'),
    (6, 'gh run list --limit 5'),
    (7, 'git push origin master'),
    (8, 'sqlite3 ~/.histdb/zsh-history.db');

insert into places(id, host, dir) values
    (1, 'demo', '/home/demo/Source/zhstdb'),
    (2, 'demo', '/home/demo/Source/zhstdb/tests'),
    (3, 'demo', '/home/demo/Source'),
    (4, 'demo', '/home/demo');

insert into history(id, session, command_id, place_id, exit_status, start_time, duration) values
    (1, 4, 1, 1, 0, unixepoch('now') - 45, 1),
    (2, 4, 2, 1, 0, unixepoch('now') - 180, 1),
    (3, 4, 3, 1, 0, unixepoch('now') - 420, 2),
    (4, 4, 4, 1, 0, unixepoch('now') - 800, 3),
    (5, 4, 5, 2, 0, unixepoch('now') - 1200, 4),
    (6, 3, 6, 1, 0, unixepoch('now') - 2400, 1),
    (7, 3, 7, 1, 0, unixepoch('now') - 3600, 2),
    (8, 2, 8, 4, 0, unixepoch('now') - 7200, 1);
