
@echo off
set PYTHONIOENCODING=utf-8
cd /d C:\KKT
python kkt_dump_tables.py --ip 192.168.137.111 --output C:\KKT\tables_dump.txt > C:\KKT\dump_log.txt 2>&1
echo EXIT_CODE=%ERRORLEVEL% >> C:\KKT\dump_log.txt
