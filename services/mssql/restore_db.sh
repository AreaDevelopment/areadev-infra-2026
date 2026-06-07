#!/bin/bash
# Restore the AreaDevelopment database from backup
# Usage: docker exec infra-mssql /var/opt/mssql/restore_db.sh [backup_file]
set -e

BACKUP_FILE="${1:-/var/opt/mssql/backup/areadevelopment.bak}"
SA_PASSWORD="${SA_PASSWORD:-YourStrongPassword123}"

if [ ! -f "$BACKUP_FILE" ]; then
    echo "ERROR: Backup file not found: $BACKUP_FILE"
    echo "Place the .bak file in the backup volume and try again."
    exit 1
fi

echo "Restoring database from: $BACKUP_FILE"

# Get logical file names from the backup
echo "Checking backup file contents..."
/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$SA_PASSWORD" -C -Q "
RESTORE FILELISTONLY FROM DISK = '$BACKUP_FILE'
" -b

echo "Restoring database..."
/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$SA_PASSWORD" -C -Q "
RESTORE DATABASE [AreaDevelopment] FROM DISK = '$BACKUP_FILE'
WITH MOVE 'AreaDevelopment' TO '/var/opt/mssql/data/AreaDevelopment.mdf',
     MOVE 'AreaDevelopment_log' TO '/var/opt/mssql/data/AreaDevelopment_log.ldf',
     REPLACE
" -b

echo "Database restore complete."
