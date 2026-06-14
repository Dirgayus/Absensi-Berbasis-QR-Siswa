Importing SQLite data into MySQL

Recommended direct migration with Node.js

1) Install dependencies inside `tools/`

     ```bash
     cd tools
     npm install
     ```

2) Run the migration script

     ```bash
     node migrate_sqlite_to_mysql.js --sqlite /path/to/absensi_qr.db --mysql-host 127.0.0.1 --mysql-user root --mysql-password your_password --mysql-database absensi
     ```

     Add `--no-create-schema` if the tables already exist.

Alternative: generate SQL and import manually

1) Create MySQL schema

   - Open your MySQL client and run the file `sql/mysql_schema.sql` to create tables.

     Example (local):
     ```bash
     mysql -u root -p < sql/mysql_schema.sql
     ```

2) Generate a MySQL dump from your local SQLite DB

   - Run the exporter script (requires Python 3):
     ```bash
     python tools/export_sqlite_to_mysql.py --sqlite /path/to/absensi_qr.db --out dump_mysql.sql
     ```

3) Import the generated dump into MySQL

     ```bash
     mysql -u app_user -p absensi < dump_mysql.sql
     ```

Notes:
- The exporter maps missing time values ("-" or empty) to `00:00:00`.
- The script writes explicit `id` values; if you want to let MySQL reassign ids, edit the dump to remove id columns or import only data without `id` columns.
- Never commit or share DB credentials. Use environment variables for production.
