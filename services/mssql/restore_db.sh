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

echo "Detecting logical file names from backup..."
FILELIST=$(/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$SA_PASSWORD" -C -s'|' -W -Q "
SET NOCOUNT ON;
RESTORE FILELISTONLY FROM DISK = '$BACKUP_FILE'
" -b)

DATA_LOGICAL=$(echo "$FILELIST" | awk -F'|' '$NF ~ /^ *$/ || $4 ~ /PRIMARY/ {print $1; exit}' | tr -d '[:space:]')
LOG_LOGICAL=$(echo "$FILELIST" | awk -F'|' '$3 ~ /^ *L *$/ {print $1; exit}' | tr -d '[:space:]')

: "${DATA_LOGICAL:=AreaDevelopment}"
: "${LOG_LOGICAL:=${DATA_LOGICAL}_log}"

echo "Logical names: data=$DATA_LOGICAL, log=$LOG_LOGICAL"

echo "Restoring database..."
/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$SA_PASSWORD" -C -Q "
RESTORE DATABASE [AreaDevelopment] FROM DISK = '$BACKUP_FILE'
WITH MOVE '$DATA_LOGICAL' TO '/var/opt/mssql/data/AreaDevelopment.mdf',
     MOVE '$LOG_LOGICAL' TO '/var/opt/mssql/data/AreaDevelopment_log.ldf',
     REPLACE
" -b

echo "Database restore complete."
