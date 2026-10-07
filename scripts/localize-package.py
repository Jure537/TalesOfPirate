"""Modify only the newly generated package, never source game data."""
import sqlite3
import sys
from pathlib import Path

package = Path(sys.argv[1]).resolve()
db_path = package / 'databases' / 'gamedata.sqlite'
with sqlite3.connect(db_path.as_uri() + '?mode=rw', uri=True) as db:
    columns = [row[1] for row in db.execute('PRAGMA table_info(servers)')]
    if columns != ['id', 'name', 'region', 'gate_ips', 'valid_gate_cnt']:
        raise RuntimeError(f'Unexpected servers schema: {columns}')
    db.execute('DELETE FROM servers')
    db.execute('INSERT INTO servers VALUES (?,?,?,?,?)',
               (1, 'Local', 'Local', '127.0.0.1', 1))
    if db.execute('PRAGMA integrity_check').fetchall() != [('ok',)]:
        raise RuntimeError('Packaged SQLite database failed integrity check')
print('Packaged client server list points to 127.0.0.1:1973')
