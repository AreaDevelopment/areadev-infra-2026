# MSSQL Server 2019 with backup restore support
FROM mcr.microsoft.com/mssql/server:2019-latest

ENV ACCEPT_EULA=Y
ENV MSSQL_SA_PASSWORD=YourStrongPassword123
ENV MSSQL_PID=Developer
ENV PATH="$PATH:/opt/mssql-tools18/bin"

# Copy restore script
COPY restore_db.sh /var/opt/mssql/restore_db.sh

USER root
RUN chmod +x /var/opt/mssql/restore_db.sh

# Create backup directory
RUN mkdir -p /var/opt/mssql/backup

EXPOSE 1433

CMD ["/opt/mssql/bin/sqlservr"]
