{
    "metadata": {
        "kernelspec": {
            "name": "SQL",
            "display_name": "SQL",
            "language": "sql"
        },
        "language_info": {
            "name": "sql",
            "version": ""
        }
    },
    "nbformat_minor": 2,
    "nbformat": 4,
    "cells": [
        {
            "cell_type": "markdown",
            "source": [
                "# **Azure SQL Database Diagnostic Information Queries**\r\n",
                "- Glenn Berry \r\n",
                "- Last Modified: July 8, 2020\r\n",
                "- Twitter: GlennAlanBerry\r\n",
                "- Blog: https://glennsqlperformance.com/\r\n",
                "\r\n",
                "> **Copyright (C) 2020 Glenn Berry** \\\r\n",
                "All rights reserved.\\\r\n",
                "You may alter this code for your own *non-commercial* purposes. \\\r\n",
                "You may republish altered code as long as you include this copyright and give due credit. \\\r\n",
                "\\\r\n",
                "THIS CODE AND INFORMATION ARE PROVIDED \"AS IS\" WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE. \r\n",
                "\r\n",
                "\r\n",
                ""
            ],
            "metadata": {
                "azdata_cell_guid": "8a4fe986-eb72-4be8-bab8-4dbd51627777"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "# Server-Level Queries\r\n",
                "\r\n",
                "Make sure you are connected a user database, rather than the master system database"
            ],
            "metadata": {
                "azdata_cell_guid": "5b6ac5cd-cee9-4578-9504-08b1fa55c308"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## SQL and OS Version information for current instance  (Query 1) (Version Info)"
            ],
            "metadata": {
                "azdata_cell_guid": "30d70523-a17f-4cca-83f4-44c25c6cc12d"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- SQL and OS Version information for current instance  (Query 1) (Version Info)\r\n",
                "SELECT @@SERVERNAME AS [Server Name], @@VERSION AS [SQL Server and OS Version Info];"
            ],
            "metadata": {
                "azdata_cell_guid": "56d600ed-93fd-4fff-8d3b-c0dfdf033fbf",
                "tags": [
                    "hide_input"
                ]
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "Useful links related to the above query:\r\n",
                "* [Download and install Azure Data Studio](https://bit.ly/2vgke1A)"
            ],
            "metadata": {
                "azdata_cell_guid": "c67f68fc-4b1a-41b5-968c-80ef608bf9b3"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Get instance-level configuration values for instance  (Query 2) (Configuration Values)"
            ],
            "metadata": {
                "azdata_cell_guid": "6f4b2c84-abac-4e11-b736-8fc4b56cd4ed"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Get instance-level configuration values for instance  (Query 2) (Configuration Values)\r\n",
                "SELECT name, value, value_in_use, minimum, maximum, [description], is_dynamic, is_advanced\r\n",
                "FROM sys.configurations WITH (NOLOCK)\r\n",
                "ORDER BY name OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "09293db1-9a77-4c48-92f1-c7d41894f933",
                "tags": [
                    "hide_input"
                ]
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "**All of these settings are read-only in Azure SQL Database, so they are informational only**\r\n",
                "- \r\n",
                "[sys.configurations (Transact-SQL)](https://bit.ly/2HsyDZI)"
            ],
            "metadata": {
                "azdata_cell_guid": "1b2643f1-a51f-4979-bfd5-a4aeb0f2c64e"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## SQL Server NUMA Node information  (Query 3) (SQL Server NUMA Info)"
            ],
            "metadata": {
                "azdata_cell_guid": "41af2734-b348-4d22-9c56-a9a5680c4df9"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- SQL Server NUMA Node information  (Query 3) (SQL Server NUMA Info)\r\n",
                "SELECT node_id, node_state_desc, memory_node_id, processor_group, cpu_count, online_scheduler_count, \r\n",
                "       idle_scheduler_count, active_worker_count, avg_load_balance, resource_monitor_state\r\n",
                "FROM sys.dm_os_nodes WITH (NOLOCK) \r\n",
                "WHERE node_state_desc <> N'ONLINE DAC' OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "12aad206-63d7-45e5-931b-d7d3b6ba0473",
                "tags": [
                    "hide_input"
                ]
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "Gives you some useful information about the composition and relative load on your NUMA nodes\r\n",
                "\r\n",
                "- You want to see an equal number of schedulers on each NUMA node\r\n",
                "\r\n",
                "\r\n",
                "[sys.dm_os_nodes (Transact-SQL)](https://bit.ly/2pn5Mw8)\r\n",
                "\r\n",
                ""
            ],
            "metadata": {
                "azdata_cell_guid": "510439a6-15ab-4097-beb9-cb32368ee294"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "Shows you the total and free space on the LUNs where you have database files\r\n",
                "- Being low on free space can negatively affect performance\r\n",
                "\r\n",
                "[sys.dm_os_volume_stats (Transact-SQL)](https://bit.ly/2oBPNNr)\r\n",
                ""
            ],
            "metadata": {
                "azdata_cell_guid": "92d6950b-fd0e-4070-a44f-a0acd054b2d6"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Calculates average latency per read, per write, and per total input/output for each database file  (Query 4) (IO Stalls by File)"
            ],
            "metadata": {
                "azdata_cell_guid": "e8034da3-9f7e-43df-82bc-27e103a3978c"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Calculates average stalls per read, per write, and per total input/output for each database file  (Query 4) (IO Stalls by File)\r\n",
                "SELECT DB_NAME(fs.database_id) AS [Database Name], CAST(fs.io_stall_read_ms/(1.0 + fs.num_of_reads) AS NUMERIC(16,1)) AS [avg_read_stall_ms],\r\n",
                "CAST(fs.io_stall_write_ms/(1.0 + fs.num_of_writes) AS NUMERIC(16,1)) AS [avg_write_stall_ms],\r\n",
                "CAST((fs.io_stall_read_ms + fs.io_stall_write_ms)/(1.0 + fs.num_of_reads + fs.num_of_writes) AS NUMERIC(16,1)) AS [avg_io_stall_ms],\r\n",
                "fs.io_stall_read_ms, fs.num_of_reads, \r\n",
                "fs.io_stall_write_ms, fs.num_of_writes, fs.io_stall_read_ms + fs.io_stall_write_ms AS [io_stalls], fs.num_of_reads + fs.num_of_writes AS [total_io],\r\n",
                "io_stall_queued_read_ms AS [Resource Governor Total Read IO Latency (ms)], io_stall_queued_write_ms AS [Resource Governor Total Write IO Latency (ms)]\r\n",
                "FROM sys.dm_io_virtual_file_stats(null,null) AS fs\r\n",
                "ORDER BY avg_io_stall_ms DESC OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "cd707a07-913b-403a-aa5a-522bc914e49a",
                "tags": [
                    "hide_input"
                ]
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "Helps determine which database files on the entire instance have the most I/O bottlenecks\r\n",
                "- This can help you decide whether certain LUNs are overloaded \r\n",
                "- Or whether you might want to move some files to a different location or perhaps improve your I/O performance\r\n",
                "- These latency numbers include all file activity against each SQL Server database file since SQL Server was last started\r\n",
                ""
            ],
            "metadata": {
                "azdata_cell_guid": "894c4d4b-ecb0-4e2f-8036-5cc03893cb0c"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Get I/O utilization by database (Query 5) (IO Usage By Database)"
            ],
            "metadata": {
                "azdata_cell_guid": "4a21658f-4a40-413d-b5df-ba343bfdb094"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Get I/O utilization by database (Query 5) (IO Usage By Database)\r\n",
                "WITH Aggregate_IO_Statistics\r\n",
                "AS (SELECT DB_NAME(database_id) AS [Database Name],\r\n",
                "    CAST(SUM(num_of_bytes_read + num_of_bytes_written) / 1048576 AS DECIMAL(12, 2)) AS [ioTotalMB],\r\n",
                "    CAST(SUM(num_of_bytes_read ) / 1048576 AS DECIMAL(12, 2)) AS [ioReadMB],\r\n",
                "    CAST(SUM(num_of_bytes_written) / 1048576 AS DECIMAL(12, 2)) AS [ioWriteMB]\r\n",
                "    FROM sys.dm_io_virtual_file_stats(NULL, NULL) AS [DM_IO_STATS]\r\n",
                "    GROUP BY database_id)\r\n",
                "SELECT ROW_NUMBER() OVER (ORDER BY ioTotalMB DESC) AS [I/O Rank],\r\n",
                "        [Database Name], ioTotalMB AS [Total I/O (MB)],\r\n",
                "        CAST(ioTotalMB / SUM(ioTotalMB) OVER () * 100.0 AS DECIMAL(5, 2)) AS [Total I/O %],\r\n",
                "        ioReadMB AS [Read I/O (MB)], \r\n",
                "\t\tCAST(ioReadMB / SUM(ioReadMB) OVER () * 100.0 AS DECIMAL(5, 2)) AS [Read I/O %],\r\n",
                "        ioWriteMB AS [Write I/O (MB)], \r\n",
                "\t\tCAST(ioWriteMB / SUM(ioWriteMB) OVER () * 100.0 AS DECIMAL(5, 2)) AS [Write I/O %]\r\n",
                "FROM Aggregate_IO_Statistics\r\n",
                "ORDER BY [I/O Rank] OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "2fc840e8-cd32-46ff-b59b-03a101834496",
                "tags": [
                    "hide_input"
                ]
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "Helps determine which database is using the most I/O resources on the instance\r\n",
                "- These numbers are cumulative since the last service restart\r\n",
                "- They include all I/O activity, not just the nominal I/O workload"
            ],
            "metadata": {
                "azdata_cell_guid": "b6153206-63b3-4c9f-ab11-3a0db3fd03b0"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Get total buffer usage by database for current instance  (Query 6) (Total Buffer Usage by Database)"
            ],
            "metadata": {
                "azdata_cell_guid": "e525a356-0a95-470b-bdd8-3200554d78ca"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Get total buffer usage by database for current instance  (Query 6) (Total Buffer Usage by Database)\r\n",
                "-- This make take some time to run on a busy instance\r\n",
                "WITH AggregateBufferPoolUsage\r\n",
                "AS\r\n",
                "(SELECT DB_NAME(database_id) AS [Database Name],\r\n",
                "CAST(COUNT(*) * 8/1024.0 AS DECIMAL (10,2))  AS [CachedSize]\r\n",
                "FROM sys.dm_os_buffer_descriptors WITH (NOLOCK)\r\n",
                "WHERE database_id <> 32767 -- ResourceDB\r\n",
                "GROUP BY DB_NAME(database_id))\r\n",
                "SELECT ROW_NUMBER() OVER(ORDER BY CachedSize DESC) AS [Buffer Pool Rank], [Database Name], CachedSize AS [Cached Size (MB)],\r\n",
                "       CAST(CachedSize / SUM(CachedSize) OVER() * 100.0 AS DECIMAL(5,2)) AS [Buffer Pool Percent]\r\n",
                "FROM AggregateBufferPoolUsage\r\n",
                "ORDER BY [Buffer Pool Rank] OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "44a1e6b7-465e-464f-bb6a-26fe065f1ddb",
                "tags": [
                    "hide_input"
                ]
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "Tells you how much memory (in the buffer pool) is being used by each database on the instance"
            ],
            "metadata": {
                "azdata_cell_guid": "87952d23-6243-4221-8343-ab47c53a64a6"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Get a count of SQL connections by IP address (Query 7) (Connection Counts by IP Address)"
            ],
            "metadata": {
                "azdata_cell_guid": "0299b6cd-25bd-4e92-be3d-1b0a26828a90"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Get a count of SQL connections by IP address (Query 7) (Connection Counts by IP Address)\r\n",
                "SELECT ec.client_net_address, es.[program_name], es.[host_name], es.login_name, \r\n",
                "COUNT(ec.session_id) AS [connection count] \r\n",
                "FROM sys.dm_exec_sessions AS es WITH (NOLOCK) \r\n",
                "INNER JOIN sys.dm_exec_connections AS ec WITH (NOLOCK) \r\n",
                "ON es.session_id = ec.session_id \r\n",
                "GROUP BY ec.client_net_address, es.[program_name], es.[host_name], es.login_name  \r\n",
                "ORDER BY ec.client_net_address, es.[program_name] OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "db876f19-dd2b-4af0-bbfa-d5792482a144",
                "tags": [
                    "hide_input"
                ]
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "This helps you figure where your database load is coming from and verifies connectivity from other machines\r\n",
                "\r\n",
                "[Solving Connectivity errors to SQL Server](https://bit.ly/2EgzoD0)"
            ],
            "metadata": {
                "azdata_cell_guid": "092aa409-ae8e-426c-b964-e536ee484fcc"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Get Average Task Counts (run multiple times)  (Query 8) (Avg Task Counts)"
            ],
            "metadata": {
                "azdata_cell_guid": "ed4204b4-820a-4266-adc0-ae5fb48360a8"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Get Average Task Counts (run multiple times)  (Query 8) (Avg Task Counts)\r\n",
                "SELECT AVG(current_tasks_count) AS [Avg Task Count], \r\n",
                "AVG(work_queue_count) AS [Avg Work Queue Count],\r\n",
                "AVG(runnable_tasks_count) AS [Avg Runnable Task Count],\r\n",
                "AVG(pending_disk_io_count) AS [Avg Pending DiskIO Count]\r\n",
                "FROM sys.dm_os_schedulers WITH (NOLOCK)\r\n",
                "WHERE scheduler_id < 255 OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "63a39346-8685-4a6f-939f-51775204d0dd",
                "tags": [
                    "hide_input"
                ]
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "Sustained values above 10 suggest further investigation in that area (depending on your Service Tier)\r\n",
                "- High Avg Task Counts are often caused by blocking/deadlocking or other resource contention\r\n",
                "\r\n",
                "Sustained values above 1 suggest further investigation in that area\r\n",
                "- High Avg Runnable Task Counts are a good sign of CPU pressure\r\n",
                "- High Avg Pending DiskIO Counts are a sign of disk pressure\r\n",
                "\r\n",
                ""
            ],
            "metadata": {
                "azdata_cell_guid": "4500bb2c-6025-45fe-ad05-a54cc9a86a68"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Detect blocking (run multiple times)  (Query 9) (Detect Blocking)"
            ],
            "metadata": {
                "azdata_cell_guid": "76df2148-9a87-4642-9dfa-aae374ca8be1"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Detect blocking (run multiple times)  (Query 9) (Detect Blocking)\r\n",
                "SELECT t1.resource_type AS [lock type], DB_NAME(resource_database_id) AS [database],\r\n",
                "t1.resource_associated_entity_id AS [blk object],t1.request_mode AS [lock req],  -- lock requested\r\n",
                "t1.request_session_id AS [waiter sid], t2.wait_duration_ms AS [wait time],       -- spid of waiter  \r\n",
                "(SELECT [text] FROM sys.dm_exec_requests AS r WITH (NOLOCK)                      -- get sql for waiter\r\n",
                "CROSS APPLY sys.dm_exec_sql_text(r.[sql_handle]) \r\n",
                "WHERE r.session_id = t1.request_session_id) AS [waiter_batch],\r\n",
                "(SELECT SUBSTRING(qt.[text],r.statement_start_offset/2, \r\n",
                "    (CASE WHEN r.statement_end_offset = -1 \r\n",
                "    THEN LEN(CONVERT(nvarchar(max), qt.[text])) * 2 \r\n",
                "    ELSE r.statement_end_offset END - r.statement_start_offset)/2) \r\n",
                "FROM sys.dm_exec_requests AS r WITH (NOLOCK)\r\n",
                "CROSS APPLY sys.dm_exec_sql_text(r.[sql_handle]) AS qt\r\n",
                "WHERE r.session_id = t1.request_session_id) AS [waiter_stmt],\t\t\t\t\t-- statement blocked\r\n",
                "t2.blocking_session_id AS [blocker sid],\t\t\t\t\t\t\t\t\t\t-- spid of blocker\r\n",
                "(SELECT [text] FROM sys.sysprocesses AS p\t\t\t\t\t\t\t\t\t\t-- get sql for blocker\r\n",
                "CROSS APPLY sys.dm_exec_sql_text(p.[sql_handle]) \r\n",
                "WHERE p.spid = t2.blocking_session_id) AS [blocker_batch]\r\n",
                "FROM sys.dm_tran_locks AS t1 WITH (NOLOCK)\r\n",
                "INNER JOIN sys.dm_os_waiting_tasks AS t2 WITH (NOLOCK)\r\n",
                "ON t1.lock_owner_address = t2.resource_address OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "b9bd2930-e5bc-4415-9d89-4ccfc0be9334",
                "tags": [
                    "hide_input"
                ]
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "Helps troubleshoot blocking and deadlocking issues\r\n",
                "- The results will change from second to second on a busy system\r\n",
                "- You should run this query multiple times when you see signs of blocking"
            ],
            "metadata": {
                "azdata_cell_guid": "15412a8a-2e65-4b59-a904-ca3012cf6528"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Page Life Expectancy (PLE) value for each NUMA node in current instance  (Query 10) (PLE by NUMA Node)"
            ],
            "metadata": {
                "azdata_cell_guid": "20f52f6d-f822-4866-9148-d9b30fc07911"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Page Life Expectancy (PLE) value for each NUMA node in current instance  (Query 10) (PLE by NUMA Node)\r\n",
                "SELECT @@SERVERNAME AS [Server Name], RTRIM([object_name]) AS [Object Name], \r\n",
                "       instance_name, cntr_value AS [Page Life Expectancy]\r\n",
                "FROM sys.dm_os_performance_counters WITH (NOLOCK)\r\n",
                "WHERE [object_name] LIKE N'%Buffer Node%' -- Handles named instances\r\n",
                "AND counter_name = N'Page life expectancy' OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "5f4d7fa6-9f97-483f-b8a8-d39740e6d977",
                "tags": [
                    "hide_input"
                ]
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "PLE is a good measurement of internal memory pressure\r\n",
                "- Higher PLE is better. Watch the trend over time, not the absolute value\r\n",
                "- This will only return one row for non-NUMA systems\r\n",
                "\r\n",
                "[Page Life Expectancy isn’t what you think…](https://bit.ly/2EgynLa)"
            ],
            "metadata": {
                "azdata_cell_guid": "ea3b0a9b-cec4-48f2-a567-00463c4e4751"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Memory Grants Pending value for current instance  (Query 11) (Memory Grants Pending)"
            ],
            "metadata": {
                "azdata_cell_guid": "44308f96-e53e-4ead-94cb-281f705da51e"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Memory Grants Pending value for current instance  (Query 11) (Memory Grants Pending)\r\n",
                "SELECT @@SERVERNAME AS [Server Name], RTRIM([object_name]) AS [Object Name], cntr_value AS [Memory Grants Pending]                                                                                                       \r\n",
                "FROM sys.dm_os_performance_counters WITH (NOLOCK)\r\n",
                "WHERE [object_name] LIKE N'%Memory Manager%' -- Handles named instances\r\n",
                "AND counter_name = N'Memory Grants Pending' OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "04cf9c86-c55f-4de9-b23c-e2bb38264632",
                "tags": [
                    "hide_input"
                ]
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "Run multiple times, and run periodically if you suspect you are under memory pressure\r\n",
                "- Memory Grants Pending above zero for a sustained period is a very strong indicator of internal memory pressure"
            ],
            "metadata": {
                "azdata_cell_guid": "1cbe791a-3035-4d08-86d7-f7d01b17f015"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Memory Clerk Usage for instance  (Query 12) (Memory Clerk Usage)"
            ],
            "metadata": {
                "azdata_cell_guid": "c4c3cac5-c806-414d-a1bf-7e759ea761b1"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Memory Clerk Usage for instance  (Query 12) (Memory Clerk Usage)\r\n",
                "-- Look for high value for CACHESTORE_SQLCP (Ad-hoc query plans)\r\n",
                "SELECT TOP(10) mc.[type] AS [Memory Clerk Type], \r\n",
                "       CAST((SUM(mc.pages_kb)/1024.0) AS DECIMAL (15,2)) AS [Memory Usage (MB)] \r\n",
                "FROM sys.dm_os_memory_clerks AS mc WITH (NOLOCK)\r\n",
                "GROUP BY mc.[type]  \r\n",
                "ORDER BY SUM(mc.pages_kb) DESC OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "3e3d1117-f22b-40a0-90a0-bda703172e4e",
                "tags": [
                    "hide_input"
                ]
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "**MEMORYCLERK_SQLBUFFERPOOL** was new for SQL Server 2012. It should be your highest consumer of memory\r\n",
                "\r\n",
                "**CACHESTORE_SQLCP** - SQL Plans         \r\n",
                "- These are cached SQL statements or batches that aren't in stored procedures, functions and triggers\r\n",
                "- Watch out for high values for CACHESTORE_SQLCP\r\n",
                "- Enabling 'optimize for ad hoc workloads' at the instance level can help reduce this\r\n",
                "- Running DBCC FREESYSTEMCACHE ('SQL Plans') periodically may be required to better control this\r\n",
                "\r\n",
                "**CACHESTORE_OBJCP** - Object Plans      \r\n",
                "- These are compiled plans for stored procedures, functions and triggers\r\n",
                "\r\n",
                "[sys.dm_os_memory_clerks (Transact-SQL)](https://bit.ly/2H31xDR)"
            ],
            "metadata": {
                "azdata_cell_guid": "c460d280-862e-4bcf-a1f8-60ca931af2e7"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Find single-use, ad-hoc and prepared queries that are bloating the plan cache  (Query 13) (Ad hoc Queries)"
            ],
            "metadata": {
                "azdata_cell_guid": "8c166c58-ca7f-4fa5-9f6f-d4570ddf2020"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Find single-use, ad-hoc and prepared queries that are bloating the plan cache  (Query 13) (Ad hoc Queries)\r\n",
                "SELECT TOP(50) DB_NAME(t.[dbid]) AS [Database Name], t.[text] AS [Query Text], \r\n",
                "cp.objtype AS [Object Type], cp.cacheobjtype AS [Cache Object Type],  \r\n",
                "cp.size_in_bytes/1024 AS [Plan Size in KB]\r\n",
                "FROM sys.dm_exec_cached_plans AS cp WITH (NOLOCK)\r\n",
                "CROSS APPLY sys.dm_exec_sql_text(plan_handle) AS t\r\n",
                "WHERE cp.cacheobjtype = N'Compiled Plan' \r\n",
                "AND cp.objtype IN (N'Adhoc', N'Prepared') \r\n",
                "AND cp.usecounts = 1\r\n",
                "ORDER BY cp.size_in_bytes DESC, DB_NAME(t.[dbid]) OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "50b90505-1385-4eab-b96e-7bef1d4a4e38",
                "tags": [
                    "hide_input"
                ]
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "Gives you the text, type and size of single-use ad-hoc and prepared queries that waste space in the plan cache\r\n",
                "- Enabling 'optimize for ad hoc workloads' for the instance can help (SQL Server 2008 and above only)\r\n",
                "- Running DBCC FREESYSTEMCACHE ('SQL Plans') periodically may be required to better control this\r\n",
                "- Enabling forced parameterization for the database can help, but test first!\r\n",
                "\r\n",
                "[Plan cache, adhoc workloads and clearing the single-use plan cache bloat](https://bit.ly/2EfYOkl)"
            ],
            "metadata": {
                "azdata_cell_guid": "c8da4d1c-4993-48f4-a9fa-2982490cdca0"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "Helps you find the most expensive queries from a memory perspective across the entire instance\r\n",
                "- Can also help track down parameter sniffing issues"
            ],
            "metadata": {
                "azdata_cell_guid": "4a764f0c-9b44-49eb-b798-a9ae2e1c2673"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "# Database specific queries\r\n",
                "\r\n",
                "> **Note**: Please switch to a user database that you are interested in!"
            ],
            "metadata": {
                "azdata_cell_guid": "f0445542-eea4-44a4-9bef-e0131ab94c09"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- **** Please switch to a user database that you are interested in! *****\r\n",
                "--USE YourDatabaseName; -- make sure to change to an actual database on your instance, not the master system database\r\n",
                "--GO"
            ],
            "metadata": {
                "azdata_cell_guid": "3acaa59a-d091-4a10-bad5-f914c9338971",
                "tags": [
                    "hide_input"
                ]
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Azure SQL Database size  (Query 14) (Azure SQL DB Size)"
            ],
            "metadata": {
                "azdata_cell_guid": "c188b61e-fad6-47c9-967c-3d9198e0bc98"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Azure SQL Database size  (Query 14) (Azure SQL DB Size)\r\n",
                "SELECT CAST(SUM(CAST(FILEPROPERTY(name, 'SpaceUsed') AS bigint) * 8192.) / 1024 / 1024 AS DECIMAL(15,2)) AS [Database Size In MB],\r\n",
                "       CAST(SUM(CAST(FILEPROPERTY(name, 'SpaceUsed') AS bigint) * 8192.) / 1024 / 1024 / 1024 AS DECIMAL(15,2)) AS [Database Size In GB]\r\n",
                "FROM sys.database_files WITH (NOLOCK)\r\n",
                "WHERE [type_desc] = N'ROWS' OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "c28add6d-66e4-418c-a7cd-f441b4e0c6fe",
                "tags": [
                    "hide_input"
                ]
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "This gives you the actual space usage within the data file only, to match what the Azure portal shows for the database size\r\n",
                "\r\n",
                "[Determining Database Size in Azure SQL Database V12](https://bit.ly/2JjrqNh)"
            ],
            "metadata": {
                "azdata_cell_guid": "189e7df0-cf29-4d28-9024-892e09ffb655"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Individual File Sizes and space available for current database  (Query 15) (File Sizes and Space)"
            ],
            "metadata": {
                "azdata_cell_guid": "44dc42a9-0712-490c-a7d3-436cc3aad079"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Individual File Sizes and space available for current database  (Query 15) (File Sizes and Space)\r\n",
                "SELECT f.name AS [File Name] , f.physical_name AS [Physical Name], \r\n",
                "CAST((f.size/128.0) AS DECIMAL(15,2)) AS [Total Size in MB],\r\n",
                "CAST(f.size/128.0 - CAST(FILEPROPERTY(f.name, 'SpaceUsed') AS int)/128.0 AS DECIMAL(15,2)) \r\n",
                "AS [Available Space In MB], f.[file_id], fg.name AS [Filegroup Name],\r\n",
                "f.is_percent_growth, f.growth, fg.is_default, fg.is_read_only, \r\n",
                "fg.is_autogrow_all_files\r\n",
                "FROM sys.database_files AS f WITH (NOLOCK) \r\n",
                "LEFT OUTER JOIN sys.filegroups AS fg WITH (NOLOCK)\r\n",
                "ON f.data_space_id = fg.data_space_id\r\n",
                "ORDER BY f.[file_id] OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "afab3607-97d0-406c-829f-e4eee79b1ee9",
                "tags": [
                    "hide_input"
                ]
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "Look at how large and how full the files are and where they are located\r\n",
                "- Make sure the transaction log is not full!!\r\n",
                "- is_autogrow_all_files was new for SQL Server 2016. Equivalent to TF 1117 for user databases\r\n",
                "\r\n",
                "[SQL Server 2016: Changes in default behavior for autogrow and allocations for tempdb and user databases](https://bit.ly/2evRZSR)"
            ],
            "metadata": {
                "azdata_cell_guid": "a05e2235-d5e1-496c-b4e4-1c9e4794d7a8"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Log space usage for current database  (Query 16) (Log Space Usage)"
            ],
            "metadata": {
                "azdata_cell_guid": "d18709d8-7651-46a0-b69a-dd4b656f459d"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Log space usage for current database  (Query 16) (Log Space Usage)\r\n",
                "SELECT DB_NAME(lsu.database_id) AS [Database Name], db.recovery_model_desc AS [Recovery Model],\r\n",
                "\t\tCAST(lsu.total_log_size_in_bytes/1048576.0 AS DECIMAL(10, 2)) AS [Total Log Space (MB)],\r\n",
                "\t\tCAST(lsu.used_log_space_in_bytes/1048576.0 AS DECIMAL(10, 2)) AS [Used Log Space (MB)], \r\n",
                "\t\tCAST(lsu.used_log_space_in_percent AS DECIMAL(10, 2)) AS [Used Log Space %],\r\n",
                "\t\tCAST(lsu.log_space_in_bytes_since_last_backup/1048576.0 AS DECIMAL(10, 2)) AS [Used Log Space Since Last Backup (MB)],\r\n",
                "\t\tdb.log_reuse_wait_desc\t\t \r\n",
                "FROM sys.dm_db_log_space_usage AS lsu WITH (NOLOCK)\r\n",
                "INNER JOIN sys.databases AS db WITH (NOLOCK)\r\n",
                "ON lsu.database_id = db.database_id\r\n",
                "OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "9a028009-ac0d-460f-8298-f924f90bfa25",
                "tags": [
                    "hide_input"
                ]
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "Look at log file size and usage, along with the log reuse wait description for the current database\r\n",
                "\r\n",
                "[sys.dm_db_log_space_usage (Transact-SQL)](https://bit.ly/2H4MQw9)"
            ],
            "metadata": {
                "azdata_cell_guid": "c4a0d470-f1f1-481a-a65e-a671c2855ba2"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Get VLF Count for current database (Query 17) (VLF Counts)"
            ],
            "metadata": {
                "azdata_cell_guid": "7b994ac2-be5e-4949-b8c1-45bd97183bca"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Get VLF Count for current database (Query 17) (VLF Counts)\r\n",
                "SELECT [name] AS [Database Name], [VLF Count]\r\n",
                "FROM sys.databases AS db WITH (NOLOCK)\r\n",
                "CROSS APPLY (SELECT file_id, COUNT(*) AS [VLF Count]\r\n",
                "\t\t     FROM sys.dm_db_log_info(db.database_id)\r\n",
                "\t\t\t GROUP BY file_id) AS li\r\n",
                "WHERE [name] <> N'master'\r\n",
                "ORDER BY [VLF Count] DESC OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "0de76a54-ac9d-45c6-9297-25ccf4b74fcf",
                "tags": [
                    "hide_input"
                ]
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "- High VLF counts can affect write performance to the log file and they can make full database restores and crash recovery take much longer\r\n",
                "- Try to keep your VLF counts under 200 in most cases (depending on log file size)"
            ],
            "metadata": {
                "azdata_cell_guid": "ad5411d8-f7be-4402-9035-f151866e736c"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Status of last VLF for current database  (Query 18) (Last VLF Status)"
            ],
            "metadata": {
                "azdata_cell_guid": "a1d08900-e245-45cd-999d-182449b9adf0"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Status of last VLF for current database  (Query 18) (Last VLF Status)\r\n",
                "SELECT TOP(1) DB_NAME(li.database_id) AS [Database Name], li.[file_id],\r\n",
                "              li.vlf_size_mb, li.vlf_sequence_number, li.vlf_active, li.vlf_status\r\n",
                "FROM sys.dm_db_log_info(DB_ID()) AS li \r\n",
                "ORDER BY vlf_sequence_number DESC OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "7979b706-6aaa-49ed-9742-c64fb2f2bdd3",
                "tags": [
                    "hide_input"
                ]
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "Determine whether you will be able to shrink the transaction log file\r\n",
                "\r\n",
                "vlf_status Values\r\n",
                "- 0 is inactive \r\n",
                "- 1 is initialized but unused \r\n",
                "- 2 is active\r\n",
                "\r\n",
                "[sys.dm_db_log_info (Transact-SQL)](https://bit.ly/2EQUU1v)"
            ],
            "metadata": {
                "azdata_cell_guid": "d502d792-1b1e-4848-86c4-40c96dfac8e5"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Important database properties for current database   (Query 19) (Database Properties)"
            ],
            "metadata": {
                "azdata_cell_guid": "06150497-4a17-4f86-be43-164a803d1efa"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Important database properties for current database   (Query 19) (Database Properties)\r\n",
                "SELECT db.[name] AS [Database Name], db.recovery_model_desc AS [Recovery Model], \r\n",
                "db.state_desc, db.containment_desc, db.log_reuse_wait_desc AS [Log Reuse Wait Description], \r\n",
                "db.[compatibility_level] AS [DB Compatibility Level], \r\n",
                "db.is_mixed_page_allocation_on, db.page_verify_option_desc AS [Page Verify Option], \r\n",
                "db.is_auto_create_stats_on, db.is_auto_update_stats_on, db.is_auto_update_stats_async_on, db.is_parameterization_forced, \r\n",
                "db.snapshot_isolation_state_desc, db.is_read_committed_snapshot_on, db.is_auto_close_on, db.is_auto_shrink_on, \r\n",
                "db.target_recovery_time_in_seconds, db.is_cdc_enabled, db.is_memory_optimized_elevate_to_snapshot_on, \r\n",
                "db.delayed_durability_desc, db.is_auto_create_stats_incremental_on,\r\n",
                "db.is_query_store_on, db.is_sync_with_backup, db.is_temporal_history_retention_enabled,\r\n",
                "db.is_encrypted, is_result_set_caching_on, is_accelerated_database_recovery_on, is_tempdb_spill_to_remote_store  \r\n",
                "FROM sys.databases AS db WITH (NOLOCK)\r\n",
                "WHERE db.[name] <> N'master'\r\n",
                "ORDER BY db.[name] OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "2717c53f-8199-4d3c-b7ad-55d633ac579d",
                "tags": [
                    "hide_input"
                ]
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "Things to look at:\r\n",
                "- What recovery model are you using?\r\n",
                "- What is the log reuse wait description?\r\n",
                "- What compatibility level is the database on? \r\n",
                "- What is the Page Verify Option? (should be CHECKSUM)\r\n",
                "- Is Auto Update Statistics Asynchronously enabled?\r\n",
                "- Is Delayed Durability enabled?"
            ],
            "metadata": {
                "azdata_cell_guid": "5700d9a2-f194-4f23-bc37-c7c842448f51"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Get database scoped configuration values for current database (Query 20) (Database-scoped Configurations)"
            ],
            "metadata": {
                "azdata_cell_guid": "454ec670-3a7a-462b-8d48-cdcad3ec052f"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Get database scoped configuration values for current database (Query 20) (Database-scoped Configurations)\r\n",
                "SELECT configuration_id, name, [value] AS [value_for_primary], value_for_secondary\r\n",
                "FROM sys.database_scoped_configurations WITH (NOLOCK) OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "3aaf1153-d510-4a91-9a70-f165b15ea216",
                "tags": [
                    "hide_input"
                ]
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "This lets you see the value of these new properties for the current database\r\n",
                "\r\n",
                "Clear plan cache for current database:\r\n",
                "- `ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;`\r\n",
                ""
            ],
            "metadata": {
                "azdata_cell_guid": "088271f4-bdeb-4ee8-82e3-e7d9346a4172"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;"
            ],
            "metadata": {
                "azdata_cell_guid": "42fc55ca-2890-4e67-a881-1575c06a4dd2"
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "\r\n",
                "[ALTER DATABASE SCOPED CONFIGURATION (Transact-SQL)](https://bit.ly/2sOH7nb)"
            ],
            "metadata": {
                "azdata_cell_guid": "057660b3-65d2-454f-8d7f-fe32f92ab0bf"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## I/O Statistics by file for the current database  (Query 21) (IO Stats By File)"
            ],
            "metadata": {
                "azdata_cell_guid": "0f37264e-c938-4288-8ae0-0758acd3c24d"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- I/O Statistics by file for the current database  (Query 21) (IO Stats By File)\r\n",
                "SELECT DB_NAME(DB_ID()) AS [Database Name], df.name AS [Logical Name], vfs.[file_id], df.type_desc,\r\n",
                "df.physical_name AS [Physical Name], CAST(vfs.size_on_disk_bytes/1048576.0 AS DECIMAL(10, 2)) AS [Size on Disk (MB)],\r\n",
                "vfs.num_of_reads, vfs.num_of_writes, vfs.io_stall_read_ms, vfs.io_stall_write_ms,\r\n",
                "CAST(100. * vfs.io_stall_read_ms/(vfs.io_stall_read_ms + vfs.io_stall_write_ms) AS DECIMAL(10,1)) AS [IO Stall Reads Pct],\r\n",
                "CAST(100. * vfs.io_stall_write_ms/(vfs.io_stall_write_ms + vfs.io_stall_read_ms) AS DECIMAL(10,1)) AS [IO Stall Writes Pct],\r\n",
                "(vfs.num_of_reads + vfs.num_of_writes) AS [Writes + Reads], \r\n",
                "CAST(vfs.num_of_bytes_read/1048576.0 AS DECIMAL(10, 2)) AS [MB Read], \r\n",
                "CAST(vfs.num_of_bytes_written/1048576.0 AS DECIMAL(10, 2)) AS [MB Written],\r\n",
                "CAST(100. * vfs.num_of_reads/(vfs.num_of_reads + vfs.num_of_writes) AS DECIMAL(10,1)) AS [# Reads Pct],\r\n",
                "CAST(100. * vfs.num_of_writes/(vfs.num_of_reads + vfs.num_of_writes) AS DECIMAL(10,1)) AS [# Write Pct],\r\n",
                "CAST(100. * vfs.num_of_bytes_read/(vfs.num_of_bytes_read + vfs.num_of_bytes_written) AS DECIMAL(10,1)) AS [Read Bytes Pct],\r\n",
                "CAST(100. * vfs.num_of_bytes_written/(vfs.num_of_bytes_read + vfs.num_of_bytes_written) AS DECIMAL(10,1)) AS [Written Bytes Pct]\r\n",
                "FROM sys.dm_io_virtual_file_stats(DB_ID(), NULL) AS vfs\r\n",
                "INNER JOIN sys.database_files AS df WITH (NOLOCK)\r\n",
                "ON vfs.[file_id]= df.[file_id] OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "3d802b5a-0c1e-4602-b370-770187b91549",
                "tags": [
                    "hide_input"
                ]
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "This helps you characterize your workload better from an I/O perspective for this database\r\n",
                "- It helps you determine whether you have an OLTP or DW/DSS type of workload"
            ],
            "metadata": {
                "azdata_cell_guid": "51bc63bf-5ec8-4a19-b200-897e5a5fc5aa"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Get recent resource usage (Query 22) (Recent Resource Usage)"
            ],
            "metadata": {
                "azdata_cell_guid": "ea2016c4-cbbd-4497-9750-a7717a2f7195"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "SELECT end_time, dtu_limit, cpu_limit, avg_cpu_percent, avg_memory_usage_percent, \r\n",
                "       avg_data_io_percent, avg_log_write_percent,  xtp_storage_percent,\r\n",
                "       max_worker_percent, max_session_percent,  avg_login_rate_percent,  \r\n",
                "\t   avg_instance_cpu_percent, avg_instance_memory_percent\r\n",
                "FROM sys.dm_db_resource_stats WITH (NOLOCK) \r\n",
                "ORDER BY end_time DESC OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "4fa3a44f-5e37-45e5-bf4d-6d1733272149",
                "tags": [
                    "hide_input"
                ]
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "- Returns a row of usage metrics every 15 seconds, going back 64 minutes\r\n",
                "- The end_time column is UTC time"
            ],
            "metadata": {
                "azdata_cell_guid": "2b1a3805-d1a8-4e07-baab-004bb94ca5c8"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Get recent resource usage (Query 23) (Avg/Max Resource Usage)"
            ],
            "metadata": {
                "azdata_cell_guid": "acd5345c-2750-44cd-a8cd-c2d5f181869e"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Get recent resource usage (Query 23) (Avg/Max Resource Usage)\r\n",
                "SELECT CAST(AVG(avg_cpu_percent) AS DECIMAL(10,2)) AS [Average CPU Utilization In Percent],   \r\n",
                "       CAST(MAX(avg_cpu_percent) AS DECIMAL(10,2)) AS [Maximum CPU Utilization In Percent],   \r\n",
                "       CAST(AVG(avg_data_io_percent) AS DECIMAL(10,2)) AS [Average Data IO In Percent],   \r\n",
                "       CAST(MAX(avg_data_io_percent) AS DECIMAL(10,2)) AS [Maximum Data IO In Percent],   \r\n",
                "       CAST(AVG(avg_log_write_percent) AS DECIMAL(10,2)) AS [Average Log Write Utilization In Percent],   \r\n",
                "       CAST(MAX(avg_log_write_percent) AS DECIMAL(10,2)) AS [Maximum Log Write Utilization In Percent],   \r\n",
                "       CAST(AVG(avg_memory_usage_percent) AS DECIMAL(10,2)) AS [Average Memory Usage In Percent],   \r\n",
                "       CAST(MAX(avg_memory_usage_percent) AS DECIMAL(10,2)) AS [Maximum Memory Usage In Percent]   \r\n",
                "FROM sys.dm_db_resource_stats WITH (NOLOCK) OPTION (RECOMPILE); "
            ],
            "metadata": {
                "azdata_cell_guid": "8f93b397-9760-4253-b478-c3c105a28c79",
                "tags": [
                    "hide_input"
                ]
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Isolate top waits for this database since last restart or failover (Query 24) (Top DB Waits)"
            ],
            "metadata": {
                "azdata_cell_guid": "27b72172-db5a-45b3-94ea-04850cc11c70"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Isolate top waits for this database since last restart or failover (Query 24) (Top DB Waits)\r\n",
                "WITH [Waits] \r\n",
                "AS (SELECT wait_type, wait_time_ms/ 1000.0 AS [WaitS],\r\n",
                "          (wait_time_ms - signal_wait_time_ms) / 1000.0 AS [ResourceS],\r\n",
                "           signal_wait_time_ms / 1000.0 AS [SignalS],\r\n",
                "           waiting_tasks_count AS [WaitCount],\r\n",
                "           100.0 *  wait_time_ms / SUM (wait_time_ms) OVER() AS [Percentage],\r\n",
                "           ROW_NUMBER() OVER(ORDER BY wait_time_ms DESC) AS [RowNum]\r\n",
                "    FROM sys.dm_db_wait_stats WITH (NOLOCK)\r\n",
                "    WHERE [wait_type] NOT IN (\r\n",
                "        N'BROKER_EVENTHANDLER', N'BROKER_RECEIVE_WAITFOR', N'BROKER_TASK_STOP',\r\n",
                "\t\tN'BROKER_TO_FLUSH', N'BROKER_TRANSMITTER', N'CHECKPOINT_QUEUE',\r\n",
                "        N'CHKPT', N'CLR_AUTO_EVENT', N'CLR_MANUAL_EVENT', N'CLR_SEMAPHORE',\r\n",
                "        N'DBMIRROR_DBM_EVENT', N'DBMIRROR_EVENTS_QUEUE', N'DBMIRROR_WORKER_QUEUE',\r\n",
                "\t\tN'DBMIRRORING_CMD', N'DIRTY_PAGE_POLL', N'DISPATCHER_QUEUE_SEMAPHORE',\r\n",
                "        N'EXECSYNC', N'FSAGENT', N'FT_IFTS_SCHEDULER_IDLE_WAIT', N'FT_IFTSHC_MUTEX',\r\n",
                "        N'HADR_CLUSAPI_CALL', N'HADR_FILESTREAM_IOMGR_IOCOMPLETION', N'HADR_LOGCAPTURE_WAIT', \r\n",
                "\t\tN'HADR_NOTIFICATION_DEQUEUE', N'HADR_TIMER_TASK', N'HADR_WORK_QUEUE',\r\n",
                "        N'KSOURCE_WAKEUP', N'LAZYWRITER_SLEEP', N'LOGMGR_QUEUE', \r\n",
                "\t\tN'MEMORY_ALLOCATION_EXT', N'ONDEMAND_TASK_QUEUE',\r\n",
                "\t\tN'PREEMPTIVE_HADR_LEASE_MECHANISM', N'PREEMPTIVE_SP_SERVER_DIAGNOSTICS',\r\n",
                "\t\tN'PREEMPTIVE_ODBCOPS',\r\n",
                "\t\tN'PREEMPTIVE_OS_LIBRARYOPS', N'PREEMPTIVE_OS_COMOPS', N'PREEMPTIVE_OS_CRYPTOPS',\r\n",
                "\t\tN'PREEMPTIVE_OS_PIPEOPS', N'PREEMPTIVE_OS_AUTHENTICATIONOPS',\r\n",
                "\t\tN'PREEMPTIVE_OS_GENERICOPS', N'PREEMPTIVE_OS_VERIFYTRUST',\r\n",
                "\t\tN'PREEMPTIVE_OS_FILEOPS', N'PREEMPTIVE_OS_DEVICEOPS', N'PREEMPTIVE_OS_QUERYREGISTRY',\r\n",
                "\t\tN'PREEMPTIVE_OS_WRITEFILE',\r\n",
                "\t\tN'PREEMPTIVE_XE_CALLBACKEXECUTE', N'PREEMPTIVE_XE_DISPATCHER',\r\n",
                "\t\tN'PREEMPTIVE_XE_GETTARGETSTATE', N'PREEMPTIVE_XE_SESSIONCOMMIT',\r\n",
                "\t\tN'PREEMPTIVE_XE_TARGETINIT', N'PREEMPTIVE_XE_TARGETFINALIZE',\r\n",
                "\t\tN'PREEMPTIVE_XHTTP',\r\n",
                "        N'PWAIT_ALL_COMPONENTS_INITIALIZED', N'PWAIT_DIRECTLOGCONSUMER_GETNEXT',\r\n",
                "\t\tN'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP',\r\n",
                "\t\tN'QDS_ASYNC_QUEUE',\r\n",
                "        N'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP', N'REQUEST_FOR_DEADLOCK_SEARCH',\r\n",
                "\t\tN'RESOURCE_GOVERNOR_IDLE',\r\n",
                "\t\tN'RESOURCE_QUEUE', N'SERVER_IDLE_CHECK', N'SLEEP_BPOOL_FLUSH', N'SLEEP_DBSTARTUP',\r\n",
                "\t\tN'SLEEP_DCOMSTARTUP', N'SLEEP_MASTERDBREADY', N'SLEEP_MASTERMDREADY',\r\n",
                "        N'SLEEP_MASTERUPGRADED', N'SLEEP_MSDBSTARTUP', N'SLEEP_SYSTEMTASK', N'SLEEP_TASK',\r\n",
                "        N'SLEEP_TEMPDBSTARTUP', N'SNI_HTTP_ACCEPT', N'SP_SERVER_DIAGNOSTICS_SLEEP',\r\n",
                "\t\tN'SQLTRACE_BUFFER_FLUSH', N'SQLTRACE_INCREMENTAL_FLUSH_SLEEP', N'SQLTRACE_WAIT_ENTRIES',\r\n",
                "\t\tN'WAIT_FOR_RESULTS', N'WAITFOR', N'WAITFOR_TASKSHUTDOWN', N'WAIT_XTP_HOST_WAIT',\r\n",
                "\t\tN'WAIT_XTP_OFFLINE_CKPT_NEW_LOG', N'WAIT_XTP_CKPT_CLOSE', N'WAIT_XTP_RECOVERY',\r\n",
                "\t\tN'XE_BUFFERMGR_ALLPROCESSED_EVENT', N'XE_DISPATCHER_JOIN',\r\n",
                "        N'XE_DISPATCHER_WAIT', N'XE_LIVE_TARGET_TVF', N'XE_TIMER_EVENT')\r\n",
                "    AND waiting_tasks_count > 0)\r\n",
                "SELECT\r\n",
                "    MAX (W1.wait_type) AS [WaitType],\r\n",
                "\tCAST (MAX (W1.Percentage) AS DECIMAL (5,2)) AS [Wait Percentage],\r\n",
                "\tCAST ((MAX (W1.WaitS) / MAX (W1.WaitCount)) AS DECIMAL (16,4)) AS [AvgWait_Sec],\r\n",
                "    CAST ((MAX (W1.ResourceS) / MAX (W1.WaitCount)) AS DECIMAL (16,4)) AS [AvgRes_Sec],\r\n",
                "    CAST ((MAX (W1.SignalS) / MAX (W1.WaitCount)) AS DECIMAL (16,4)) AS [AvgSig_Sec],\r\n",
                "    CAST (MAX (W1.WaitS) AS DECIMAL (16,2)) AS [Total_Wait_Sec],\r\n",
                "    CAST (MAX (W1.ResourceS) AS DECIMAL (16,2)) AS [Resource_Sec],\r\n",
                "    CAST (MAX (W1.SignalS) AS DECIMAL (16,2)) AS [Signal_Sec],\r\n",
                "    MAX (W1.WaitCount) AS [Wait Count]   \r\n",
                "FROM Waits AS W1\r\n",
                "INNER JOIN Waits AS W2\r\n",
                "ON W2.RowNum <= W1.RowNum\r\n",
                "GROUP BY W1.RowNum\r\n",
                "HAVING SUM (W2.Percentage) - MAX (W1.Percentage) < 99 -- percentage threshold\r\n",
                "OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "7d10e589-3b70-48d0-8741-18dafd5152c9",
                "tags": [
                    "hide_input"
                ]
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "Cumulative wait stats are not as useful on an idle instance that is not under load or performance pressure\r\n",
                "\r\n",
                "[SQL Server Wait Types Library](https://bit.ly/2ePzYO2)\r\n",
                "\r\n",
                "[The SQL Server Wait Type Repository](https://bit.ly/1afzfjC)\r\n",
                "\r\n",
                "[Wait statistics, or please tell me where it hurts](https://bit.ly/2wsQHQE)\r\n",
                "\r\n",
                "[SQL Server 2005 Performance Tuning using the Waits and Queues](https://bit.ly/1o2NFoF)\r\n",
                "\r\n",
                "[sys.dm_os_wait_stats (Transact-SQL)](https://bit.ly/2Hjq9Yl)\r\n",
                ""
            ],
            "metadata": {
                "azdata_cell_guid": "1eecc47c-52fd-4f87-ac3d-da61635dc177"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Get most frequently executed queries for this database (Query 25) (Query Execution Counts)"
            ],
            "metadata": {
                "azdata_cell_guid": "3cea974b-f126-4cab-86fc-4ce7e006de36"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Get most frequently executed queries for this database (Query 25) (Query Execution Counts)\r\n",
                "SELECT TOP(50) LEFT(t.[text], 50) AS [Short Query Text], qs.execution_count AS [Execution Count],\r\n",
                "qs.total_logical_reads AS [Total Logical Reads],\r\n",
                "qs.total_logical_reads/qs.execution_count AS [Avg Logical Reads],\r\n",
                "qs.total_worker_time AS [Total Worker Time],\r\n",
                "qs.total_worker_time/qs.execution_count AS [Avg Worker Time], \r\n",
                "qs.total_elapsed_time AS [Total Elapsed Time],\r\n",
                "qs.total_elapsed_time/qs.execution_count AS [Avg Elapsed Time],\r\n",
                "CASE WHEN CONVERT(nvarchar(max), qp.query_plan) COLLATE Latin1_General_BIN2 LIKE N'%<MissingIndexes>%' THEN 1 ELSE 0 END AS [Has Missing Index],\r\n",
                "qs.creation_time AS [Creation Time]\r\n",
                "--,t.[text] AS [Complete Query Text], qp.query_plan AS [Query Plan] -- uncomment out these columns if not copying results to Excel\r\n",
                "FROM sys.dm_exec_query_stats AS qs WITH (NOLOCK)\r\n",
                "CROSS APPLY sys.dm_exec_sql_text(plan_handle) AS t \r\n",
                "CROSS APPLY sys.dm_exec_query_plan(plan_handle) AS qp \r\n",
                "WHERE t.dbid = DB_ID()\r\n",
                "ORDER BY qs.execution_count DESC OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "fc55c63f-8afc-473d-b713-3e6a347a2100",
                "tags": [
                    "hide_input"
                ]
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "Tells you which cached queries are called the most often\r\n",
                "- This helps you characterize and baseline your workload\r\n",
                "- It also helps you find possible caching opportunities"
            ],
            "metadata": {
                "azdata_cell_guid": "d1fc8481-722e-4f0b-a0ba-e05b91b99298"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Get top total worker time queries for this database (Query 26) (Top Worker Time Queries)"
            ],
            "metadata": {
                "azdata_cell_guid": "890b9229-47c8-4872-9a2c-5d9569603ba4"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Get top total worker time queries for this database (Query 26) (Top Worker Time Queries)\t\t\r\n",
                "SELECT TOP(50) DB_NAME(t.[dbid]) AS [Database Name], \r\n",
                "REPLACE(REPLACE(LEFT(t.[text], 50), CHAR(10),''), CHAR(13),'') AS [Short Query Text],  \r\n",
                "qs.total_worker_time AS [Total Worker Time], qs.min_worker_time AS [Min Worker Time],\r\n",
                "qs.total_worker_time/qs.execution_count AS [Avg Worker Time], \r\n",
                "qs.max_worker_time AS [Max Worker Time], \r\n",
                "qs.min_elapsed_time AS [Min Elapsed Time], \r\n",
                "qs.total_elapsed_time/qs.execution_count AS [Avg Elapsed Time], \r\n",
                "qs.max_elapsed_time AS [Max Elapsed Time],\r\n",
                "qs.min_logical_reads AS [Min Logical Reads],\r\n",
                "qs.total_logical_reads/qs.execution_count AS [Avg Logical Reads],\r\n",
                "qs.max_logical_reads AS [Max Logical Reads], \r\n",
                "qs.execution_count AS [Execution Count],\r\n",
                "CASE WHEN CONVERT(nvarchar(max), qp.query_plan) LIKE N'%<MissingIndexes>%' THEN 1 ELSE 0 END AS [Has Missing Index],  \r\n",
                "qs.creation_time AS [Creation Time]\r\n",
                "--,t.[text] AS [Query Text], qp.query_plan AS [Query Plan] -- uncomment out these columns if not copying results to Excel\r\n",
                "FROM sys.dm_exec_query_stats AS qs WITH (NOLOCK)\r\n",
                "CROSS APPLY sys.dm_exec_sql_text(plan_handle) AS t \r\n",
                "CROSS APPLY sys.dm_exec_query_plan(plan_handle) AS qp\r\n",
                "WHERE t.dbid = DB_ID() \r\n",
                "ORDER BY qs.total_worker_time DESC OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "fa49d625-e688-45a7-84ee-1760095914dd",
                "tags": [
                    "hide_input"
                ]
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "- Helps you find the most expensive queries from a CPU perspective for this database\r\n",
                "- Can also help track down parameter sniffing issues"
            ],
            "metadata": {
                "azdata_cell_guid": "4ff5babc-c7c2-4d9b-8ed4-9db63538045a"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Get top total logical reads queries for this database (Query 27) (Top Logical Reads Queries) "
            ],
            "metadata": {
                "azdata_cell_guid": "d478f882-9868-4b67-8550-56fb413b1006"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "SELECT TOP(50) DB_NAME(t.[dbid]) AS [Database Name],\r\n",
                "REPLACE(REPLACE(LEFT(t.[text], 50), CHAR(10),''), CHAR(13),'') AS [Short Query Text], \r\n",
                "qs.total_logical_reads AS [Total Logical Reads],\r\n",
                "qs.min_logical_reads AS [Min Logical Reads],\r\n",
                "qs.total_logical_reads/qs.execution_count AS [Avg Logical Reads],\r\n",
                "qs.max_logical_reads AS [Max Logical Reads],   \r\n",
                "qs.min_worker_time AS [Min Worker Time],\r\n",
                "qs.total_worker_time/qs.execution_count AS [Avg Worker Time], \r\n",
                "qs.max_worker_time AS [Max Worker Time], \r\n",
                "qs.min_elapsed_time AS [Min Elapsed Time], \r\n",
                "qs.total_elapsed_time/qs.execution_count AS [Avg Elapsed Time], \r\n",
                "qs.max_elapsed_time AS [Max Elapsed Time],\r\n",
                "qs.execution_count AS [Execution Count],\r\n",
                "CASE WHEN CONVERT(nvarchar(max), qp.query_plan) LIKE N'%<MissingIndexes>%' THEN 1 ELSE 0 END AS [Has Missing Index],   \r\n",
                "qs.creation_time AS [Creation Time]\r\n",
                "--,t.[text] AS [Complete Query Text], qp.query_plan AS [Query Plan] -- uncomment out these columns if not copying results to Excel\r\n",
                "FROM sys.dm_exec_query_stats AS qs WITH (NOLOCK)\r\n",
                "CROSS APPLY sys.dm_exec_sql_text(plan_handle) AS t \r\n",
                "CROSS APPLY sys.dm_exec_query_plan(plan_handle) AS qp\r\n",
                "WHERE t.dbid = DB_ID()  \r\n",
                "ORDER BY qs.total_logical_reads DESC OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "93db448c-7b02-486f-8d5e-1590c1ed03b8",
                "tags": [
                    "hide_input"
                ]
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "- Helps you find the most expensive queries from a memory perspective for this database\r\n",
                "- Can also help track down parameter sniffing issues"
            ],
            "metadata": {
                "azdata_cell_guid": "6afd9b3b-e2da-4b8e-a519-53bc1acc8b70"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Get top average elapsed time queries for this database (Query 28) (Top Avg Elapsed Time Queries)"
            ],
            "metadata": {
                "azdata_cell_guid": "78425e5c-0f4a-40ad-8d4b-a310d6975e7b"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "SELECT TOP(50) DB_NAME(t.[dbid]) AS [Database Name], \r\n",
                "REPLACE(REPLACE(LEFT(t.[text], 255), CHAR(10),''), CHAR(13),'') AS [Short Query Text],  \r\n",
                "qs.total_elapsed_time/qs.execution_count AS [Avg Elapsed Time],\r\n",
                "qs.min_elapsed_time, qs.max_elapsed_time, qs.last_elapsed_time,\r\n",
                "qs.execution_count AS [Execution Count],  \r\n",
                "qs.total_logical_reads/qs.execution_count AS [Avg Logical Reads], \r\n",
                "qs.total_physical_reads/qs.execution_count AS [Avg Physical Reads], \r\n",
                "qs.total_worker_time/qs.execution_count AS [Avg Worker Time],\r\n",
                "CASE WHEN CONVERT(nvarchar(max), qp.query_plan) LIKE N'%<MissingIndexes>%' THEN 1 ELSE 0 END AS [Has Missing Index],  \r\n",
                "qs.creation_time AS [Creation Time]\r\n",
                ", qp.query_plan AS [Query Plan] -- comment out this column if copying results to Excel\r\n",
                "FROM sys.dm_exec_query_stats AS qs WITH (NOLOCK)\r\n",
                "CROSS APPLY sys.dm_exec_sql_text(plan_handle) AS t \r\n",
                "CROSS APPLY sys.dm_exec_query_plan(plan_handle) AS qp\r\n",
                "WHERE t.dbid = DB_ID()  \r\n",
                "ORDER BY qs.total_elapsed_time/qs.execution_count DESC OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "e8f4602a-17d7-4d1e-94f4-e870d9d1a6e0",
                "tags": [
                    "hide_input"
                ]
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "- Helps you find the highest average elapsed time queries for this database\r\n",
                "- Can also help track down parameter sniffing issues"
            ],
            "metadata": {
                "azdata_cell_guid": "d78f5df6-24cc-413b-8ad7-22f17e5f4083"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## **Queries 29 through 34 are the \"Bad Man List\" for stored procedures**"
            ],
            "metadata": {
                "azdata_cell_guid": "a79de6e1-5d2f-4608-b282-8fa000b0c8a1"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Top Cached SPs By Execution Count (Query 29) (SP Execution Counts)"
            ],
            "metadata": {
                "azdata_cell_guid": "49f07abb-c2ca-418d-9b03-05d76604658a"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Top Cached SPs By Execution Count (Query 29) (SP Execution Counts)\r\n",
                "SELECT TOP(100) p.name AS [SP Name], qs.execution_count AS [Execution Count],\r\n",
                "ISNULL(qs.execution_count/DATEDIFF(Minute, qs.cached_time, GETDATE()), 0) AS [Calls/Minute],\r\n",
                "qs.total_elapsed_time/qs.execution_count AS [Avg Elapsed Time],\r\n",
                "qs.total_worker_time/qs.execution_count AS [Avg Worker Time],    \r\n",
                "qs.total_logical_reads/qs.execution_count AS [Avg Logical Reads],\r\n",
                "CASE WHEN CONVERT(nvarchar(max), qp.query_plan) COLLATE Latin1_General_BIN2 LIKE N'%<MissingIndexes>%' THEN 1 ELSE 0 END AS [Has Missing Index],\r\n",
                "FORMAT(qs.last_execution_time, 'yyyy-MM-dd HH:mm:ss', 'en-US') AS [Last Execution Time], \r\n",
                "FORMAT(qs.cached_time, 'yyyy-MM-dd HH:mm:ss', 'en-US') AS [Plan Cached Time]\r\n",
                "-- ,qp.query_plan AS [Query Plan] -- Uncomment if you want the Query Plan\r\n",
                "FROM sys.procedures AS p WITH (NOLOCK)\r\n",
                "INNER JOIN sys.dm_exec_procedure_stats AS qs WITH (NOLOCK)\r\n",
                "ON p.[object_id] = qs.[object_id]\r\n",
                "CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) AS qp\r\n",
                "WHERE qs.database_id = DB_ID()\r\n",
                "AND DATEDIFF(Minute, qs.cached_time, GETDATE()) > 0\r\n",
                "ORDER BY qs.execution_count DESC OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "fdf21554-8055-4c22-ad32-7964099c3832",
                "tags": [
                    "hide_input"
                ]
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "Tells you which cached stored procedures are called the most often\r\n",
                "- This helps you characterize and baseline your workload\r\n",
                "- It also helps you find possible caching opportunities"
            ],
            "metadata": {
                "azdata_cell_guid": "9d9e31af-9456-401d-ad12-d906b53ab0bb"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Top Cached SPs By Avg Elapsed Time (Query 30) (SP Avg Elapsed Time)"
            ],
            "metadata": {
                "azdata_cell_guid": "d9d2dbfa-d50b-4758-9727-9a2bb85f114b"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Top Cached SPs By Avg Elapsed Time (Query 30) (SP Avg Elapsed Time)\r\n",
                "SELECT TOP(25) p.name AS [SP Name], qs.min_elapsed_time, qs.total_elapsed_time/qs.execution_count AS [avg_elapsed_time], \r\n",
                "qs.max_elapsed_time, qs.last_elapsed_time, qs.total_elapsed_time, qs.execution_count, \r\n",
                "ISNULL(qs.execution_count/DATEDIFF(Minute, qs.cached_time, GETDATE()), 0) AS [Calls/Minute], \r\n",
                "qs.total_worker_time/qs.execution_count AS [AvgWorkerTime], \r\n",
                "qs.total_worker_time AS [TotalWorkerTime],\r\n",
                "CASE WHEN CONVERT(nvarchar(max), qp.query_plan) COLLATE Latin1_General_BIN2 LIKE N'%<MissingIndexes>%' THEN 1 ELSE 0 END AS [Has Missing Index],\r\n",
                "FORMAT(qs.last_execution_time, 'yyyy-MM-dd HH:mm:ss', 'en-US') AS [Last Execution Time], \r\n",
                "FORMAT(qs.cached_time, 'yyyy-MM-dd HH:mm:ss', 'en-US') AS [Plan Cached Time]\r\n",
                "-- ,qp.query_plan AS [Query Plan] -- Uncomment if you want the Query Plan\r\n",
                "FROM sys.procedures AS p WITH (NOLOCK)\r\n",
                "INNER JOIN sys.dm_exec_procedure_stats AS qs WITH (NOLOCK)\r\n",
                "ON p.[object_id] = qs.[object_id]\r\n",
                "CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) AS qp\r\n",
                "WHERE qs.database_id = DB_ID()\r\n",
                "AND DATEDIFF(Minute, qs.cached_time, GETDATE()) > 0\r\n",
                "ORDER BY avg_elapsed_time DESC OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "ee649200-e259-4400-bd5a-37446e58ee52",
                "tags": [
                    "hide_input"
                ]
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "This helps you find high average elapsed time cached stored procedures that may be easy to optimize with standard query tuning techniques"
            ],
            "metadata": {
                "azdata_cell_guid": "0938ba2b-e56e-4dca-850d-922c77657f4e"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Top Cached SPs By Total Worker time. Worker time relates to CPU cost  (Query 31) (SP Worker Time)"
            ],
            "metadata": {
                "azdata_cell_guid": "62d3d97f-4f28-430f-870f-8f5d2710665a"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Top Cached SPs By Total Worker time. Worker time relates to CPU cost  (Query 31) (SP Worker Time)\r\n",
                "SELECT TOP(25) p.name AS [SP Name], qs.total_worker_time AS [TotalWorkerTime], \r\n",
                "qs.total_worker_time/qs.execution_count AS [AvgWorkerTime], qs.execution_count, \r\n",
                "ISNULL(qs.execution_count/DATEDIFF(Minute, qs.cached_time, GETDATE()), 0) AS [Calls/Minute],\r\n",
                "qs.total_elapsed_time, qs.total_elapsed_time/qs.execution_count AS [avg_elapsed_time],\r\n",
                "CASE WHEN CONVERT(nvarchar(max), qp.query_plan) COLLATE Latin1_General_BIN2 LIKE N'%<MissingIndexes>%' THEN 1 ELSE 0 END AS [Has Missing Index],\r\n",
                "FORMAT(qs.last_execution_time, 'yyyy-MM-dd HH:mm:ss', 'en-US') AS [Last Execution Time], \r\n",
                "FORMAT(qs.cached_time, 'yyyy-MM-dd HH:mm:ss', 'en-US') AS [Plan Cached Time]\r\n",
                "-- ,qp.query_plan AS [Query Plan] -- Uncomment if you want the Query Plan\r\n",
                "FROM sys.procedures AS p WITH (NOLOCK)\r\n",
                "INNER JOIN sys.dm_exec_procedure_stats AS qs WITH (NOLOCK)\r\n",
                "ON p.[object_id] = qs.[object_id]\r\n",
                "CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) AS qp\r\n",
                "WHERE qs.database_id = DB_ID()\r\n",
                "AND DATEDIFF(Minute, qs.cached_time, GETDATE()) > 0\r\n",
                "ORDER BY qs.total_worker_time DESC OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "8445ed25-3282-412f-840f-6b11095746fb",
                "tags": [
                    "hide_input"
                ]
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "This helps you find the most expensive cached stored procedures from a CPU perspective\r\n",
                "- You should look at this if you see signs of CPU pressure"
            ],
            "metadata": {
                "azdata_cell_guid": "4b69bacc-7d9c-4f3d-9846-bd150c967a71"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Top Cached SPs By Total Logical Reads. Logical reads relate to memory pressure  (Query 32) (SP Logical Reads)"
            ],
            "metadata": {
                "azdata_cell_guid": "0c5f4b2b-0f1e-4b6b-b3ef-a0a4289255cb"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Top Cached SPs By Total Logical Reads. Logical reads relate to memory pressure  (Query 32) (SP Logical Reads)\r\n",
                "SELECT TOP(25) p.name AS [SP Name], qs.total_logical_reads AS [TotalLogicalReads], \r\n",
                "qs.total_logical_reads/qs.execution_count AS [AvgLogicalReads],qs.execution_count, \r\n",
                "ISNULL(qs.execution_count/DATEDIFF(Minute, qs.cached_time, GETDATE()), 0) AS [Calls/Minute], \r\n",
                "qs.total_elapsed_time, qs.total_elapsed_time/qs.execution_count AS [avg_elapsed_time],\r\n",
                "CASE WHEN CONVERT(nvarchar(max), qp.query_plan) COLLATE Latin1_General_BIN2 LIKE N'%<MissingIndexes>%' THEN 1 ELSE 0 END AS [Has Missing Index],\r\n",
                "FORMAT(qs.last_execution_time, 'yyyy-MM-dd HH:mm:ss', 'en-US') AS [Last Execution Time], \r\n",
                "FORMAT(qs.cached_time, 'yyyy-MM-dd HH:mm:ss', 'en-US') AS [Plan Cached Time]\r\n",
                "-- ,qp.query_plan AS [Query Plan] -- Uncomment if you want the Query Plan\r\n",
                "FROM sys.procedures AS p WITH (NOLOCK)\r\n",
                "INNER JOIN sys.dm_exec_procedure_stats AS qs WITH (NOLOCK)\r\n",
                "ON p.[object_id] = qs.[object_id]\r\n",
                "CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) AS qp\r\n",
                "WHERE qs.database_id = DB_ID()\r\n",
                "AND DATEDIFF(Minute, qs.cached_time, GETDATE()) > 0\r\n",
                "ORDER BY qs.total_logical_reads DESC OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "f4683358-f8b7-42aa-b0c0-a22bd648b6ba",
                "tags": [
                    "hide_input"
                ]
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "This helps you find the most expensive cached stored procedures from a memory perspective\r\n",
                "- You should look at this if you see signs of memory pressure"
            ],
            "metadata": {
                "azdata_cell_guid": "77bd1009-60c5-4a53-b1d9-18689d38a72f"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Top Cached SPs By Total Physical Reads. Physical reads relate to disk read I/O pressure  (Query 33) (SP Physical Reads)"
            ],
            "metadata": {
                "azdata_cell_guid": "4cb0b8cf-ac19-4062-90f8-46c0f1b99d13"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Top Cached SPs By Total Physical Reads. Physical reads relate to disk read I/O pressure  (Query 33) (SP Physical Reads)\r\n",
                "SELECT TOP(25) p.name AS [SP Name],qs.total_physical_reads AS [TotalPhysicalReads], \r\n",
                "qs.total_physical_reads/qs.execution_count AS [AvgPhysicalReads], qs.execution_count, \r\n",
                "qs.total_logical_reads,qs.total_elapsed_time, qs.total_elapsed_time/qs.execution_count AS [avg_elapsed_time],\r\n",
                "CASE WHEN CONVERT(nvarchar(max), qp.query_plan) COLLATE Latin1_General_BIN2 LIKE N'%<MissingIndexes>%' THEN 1 ELSE 0 END AS [Has Missing Index],\r\n",
                "FORMAT(qs.last_execution_time, 'yyyy-MM-dd HH:mm:ss', 'en-US') AS [Last Execution Time], \r\n",
                "FORMAT(qs.cached_time, 'yyyy-MM-dd HH:mm:ss', 'en-US') AS [Plan Cached Time]\r\n",
                "-- ,qp.query_plan AS [Query Plan] -- Uncomment if you want the Query Plan \r\n",
                "FROM sys.procedures AS p WITH (NOLOCK)\r\n",
                "INNER JOIN sys.dm_exec_procedure_stats AS qs WITH (NOLOCK)\r\n",
                "ON p.[object_id] = qs.[object_id]\r\n",
                "CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) AS qp\r\n",
                "WHERE qs.database_id = DB_ID()\r\n",
                "AND qs.total_physical_reads > 0\r\n",
                "ORDER BY qs.total_physical_reads DESC, qs.total_logical_reads DESC OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "6e12499e-e224-4703-9441-7077a81219f6",
                "tags": [
                    "hide_input"
                ]
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "This helps you find the most expensive cached stored procedures from a read I/O perspective\r\n",
                "- You should look at this if you see signs of I/O pressure or of memory pressure"
            ],
            "metadata": {
                "azdata_cell_guid": "772c29f2-e36b-40ed-bcb0-4912536f0347"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Top Cached SPs By Total Logical Writes (Query 34) (SP Logical Writes)"
            ],
            "metadata": {
                "azdata_cell_guid": "24fb6506-9956-4708-b9ad-77d1ce74233c"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Top Cached SPs By Total Logical Writes (Query 34) (SP Logical Writes)\r\n",
                "-- Logical writes relate to both memory and disk I/O pressure \r\n",
                "SELECT TOP(25) p.name AS [SP Name], qs.total_logical_writes AS [TotalLogicalWrites], \r\n",
                "qs.total_logical_writes/qs.execution_count AS [AvgLogicalWrites], qs.execution_count,\r\n",
                "ISNULL(qs.execution_count/DATEDIFF(Minute, qs.cached_time, GETDATE()), 0) AS [Calls/Minute],\r\n",
                "qs.total_elapsed_time, qs.total_elapsed_time/qs.execution_count AS [avg_elapsed_time],\r\n",
                "CASE WHEN CONVERT(nvarchar(max), qp.query_plan) COLLATE Latin1_General_BIN2 LIKE N'%<MissingIndexes>%' THEN 1 ELSE 0 END AS [Has Missing Index], \r\n",
                "FORMAT(qs.last_execution_time, 'yyyy-MM-dd HH:mm:ss', 'en-US') AS [Last Execution Time], \r\n",
                "FORMAT(qs.cached_time, 'yyyy-MM-dd HH:mm:ss', 'en-US') AS [Plan Cached Time]\r\n",
                "-- ,qp.query_plan AS [Query Plan] -- Uncomment if you want the Query Plan \r\n",
                "FROM sys.procedures AS p WITH (NOLOCK)\r\n",
                "INNER JOIN sys.dm_exec_procedure_stats AS qs WITH (NOLOCK)\r\n",
                "ON p.[object_id] = qs.[object_id]\r\n",
                "CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) AS qp\r\n",
                "WHERE qs.database_id = DB_ID()\r\n",
                "AND qs.total_logical_writes > 0\r\n",
                "AND DATEDIFF(Minute, qs.cached_time, GETDATE()) > 0\r\n",
                "ORDER BY qs.total_logical_writes DESC OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "63745f92-3cef-4097-9e28-74dcc2b71d69",
                "tags": [
                    "hide_input"
                ]
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "This helps you find the most expensive cached stored procedures from a write I/O perspective\r\n",
                "- You should look at this if you see signs of I/O pressure or of memory pressure"
            ],
            "metadata": {
                "azdata_cell_guid": "d809a718-18f7-4077-91e1-8cf0753154a2"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Lists the top statements by average input/output usage for the current database  (Query 35) (Top IO Statements)"
            ],
            "metadata": {
                "azdata_cell_guid": "9b89a916-a359-4328-a297-94914d05b4ff"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Lists the top statements by average input/output usage for the current database  (Query 35) (Top IO Statements)\r\n",
                "SELECT TOP(50) OBJECT_NAME(qt.objectid, dbid) AS [SP Name],\r\n",
                "(qs.total_logical_reads + qs.total_logical_writes) /qs.execution_count AS [Avg IO], qs.execution_count AS [Execution Count],\r\n",
                "SUBSTRING(qt.[text],qs.statement_start_offset/2, \r\n",
                "\t(CASE \r\n",
                "\t\tWHEN qs.statement_end_offset = -1 \r\n",
                "\t THEN LEN(CONVERT(nvarchar(max), qt.[text])) * 2 \r\n",
                "\t\tELSE qs.statement_end_offset \r\n",
                "\t END - qs.statement_start_offset)/2) AS [Query Text]\t\r\n",
                "FROM sys.dm_exec_query_stats AS qs WITH (NOLOCK)\r\n",
                "CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS qt\r\n",
                "WHERE qt.[dbid] = DB_ID()\r\n",
                "ORDER BY [Avg IO] DESC OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "73f7709e-85f8-4d24-b0c2-8b2121327798",
                "tags": [
                    "hide_input"
                ]
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "Helps you find the most expensive statements for I/O by SP"
            ],
            "metadata": {
                "azdata_cell_guid": "a2ea67ba-0f28-4d48-b6df-7f2b97a18298"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Possible Bad NC Indexes (writes > reads)  (Query 36) (Bad NC Indexes)"
            ],
            "metadata": {
                "azdata_cell_guid": "015decc0-fce5-4334-9afd-7ca74087bac0"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Possible Bad NC Indexes (writes > reads)  (Query 36) (Bad NC Indexes)\r\n",
                "SELECT SCHEMA_NAME(o.[schema_id]) AS [Schema Name], \r\n",
                "OBJECT_NAME(s.[object_id]) AS [Table Name],\r\n",
                "i.name AS [Index Name], i.index_id, \r\n",
                "i.is_disabled, i.is_hypothetical, i.has_filter, i.fill_factor,\r\n",
                "s.user_updates AS [Total Writes], s.user_seeks + s.user_scans + s.user_lookups AS [Total Reads],\r\n",
                "s.user_updates - (s.user_seeks + s.user_scans + s.user_lookups) AS [Difference]\r\n",
                "FROM sys.dm_db_index_usage_stats AS s WITH (NOLOCK)\r\n",
                "INNER JOIN sys.indexes AS i WITH (NOLOCK)\r\n",
                "ON s.[object_id] = i.[object_id]\r\n",
                "AND i.index_id = s.index_id\r\n",
                "INNER JOIN sys.objects AS o WITH (NOLOCK)\r\n",
                "ON i.[object_id] = o.[object_id]\r\n",
                "WHERE OBJECTPROPERTY(s.[object_id],'IsUserTable') = 1\r\n",
                "AND s.database_id = DB_ID()\r\n",
                "AND s.user_updates > (s.user_seeks + s.user_scans + s.user_lookups)\r\n",
                "AND i.index_id > 1 AND i.[type_desc] = N'NONCLUSTERED'\r\n",
                "AND i.is_primary_key = 0 AND i.is_unique_constraint = 0 AND i.is_unique = 0\r\n",
                "ORDER BY [Difference] DESC, [Total Writes] DESC, [Total Reads] ASC OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "3744cb03-b05f-4f5d-94eb-6917dd2e785b",
                "tags": [
                    "hide_input"
                ]
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "Look for indexes with high numbers of writes and zero or very low numbers of reads\r\n",
                "- Consider your complete workload, and how long your instance has been running\r\n",
                "- Investigate further before dropping an index!"
            ],
            "metadata": {
                "azdata_cell_guid": "eaf67006-be78-4c58-a79b-05cf7807ad4b"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Missing Indexes for current database by Index Advantage  (Query 37) (Missing Indexes)"
            ],
            "metadata": {
                "azdata_cell_guid": "533323aa-8cb7-4093-8d82-93d0090ec47d"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Missing Indexes for current database by Index Advantage  (Query 37) (Missing Indexes)\r\n",
                "SELECT CONVERT(decimal(18,2), migs.user_seeks * migs.avg_total_user_cost * (migs.avg_user_impact * 0.01)) AS [index_advantage], \r\n",
                "FORMAT(migs.last_user_seek, 'yyyy-MM-dd HH:mm:ss') AS [last_user_seek], mid.[statement] AS [Database.Schema.Table], \r\n",
                "COUNT(1) OVER(PARTITION BY mid.[statement]) AS [missing_indexes_for_table], \r\n",
                "COUNT(1) OVER(PARTITION BY mid.[statement], mid.equality_columns) AS [similar_missing_indexes_for_table], \r\n",
                "mid.equality_columns, mid.inequality_columns, mid.included_columns, migs.user_seeks, \r\n",
                "CONVERT(decimal(18,2), migs.avg_total_user_cost) AS [avg_total_user_,cost], migs.avg_user_impact,\r\n",
                "REPLACE(REPLACE(LEFT(st.[text], 255), CHAR(10),''), CHAR(13),'') AS [Short Query Text],\r\n",
                "OBJECT_NAME(mid.[object_id]) AS [Table Name], p.rows AS [Table Rows]\r\n",
                "FROM sys.dm_db_missing_index_groups AS mig WITH (NOLOCK) \r\n",
                "INNER JOIN sys.dm_db_missing_index_group_stats_query AS migs WITH(NOLOCK) \r\n",
                "ON mig.index_group_handle = migs.group_handle \r\n",
                "CROSS APPLY sys.dm_exec_sql_text(migs.last_sql_handle) AS st \r\n",
                "INNER JOIN sys.dm_db_missing_index_details AS mid WITH (NOLOCK) \r\n",
                "ON mig.index_handle = mid.index_handle\r\n",
                "INNER JOIN sys.partitions AS p WITH (NOLOCK)\r\n",
                "ON p.[object_id] = mid.[object_id]\r\n",
                "WHERE mid.database_id = DB_ID()\r\n",
                "AND p.index_id < 2 \r\n",
                "ORDER BY index_advantage DESC OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "e4ca4552-1b71-4293-885d-1a04bb843c0a",
                "tags": [
                    "hide_input"
                ]
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "Look at index advantage, last user seek time, number of user seeks to help determine source and importance\r\n",
                "- SQL Server is overly eager to add included columns, so beware\r\n",
                "- Do not just blindly add indexes that show up from this query!!!\r\n",
                "\r\n",
                "Håkan Winther has given me some great suggestions for this query"
            ],
            "metadata": {
                "azdata_cell_guid": "0f638adc-52a3-4699-b890-f14128b3f4a8"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Find missing index warnings for cached plans in the current database  (Query 38) (Missing Index Warnings)"
            ],
            "metadata": {
                "azdata_cell_guid": "642e72dd-3375-470f-a36d-6a5e40151c0a"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Find missing index warnings for cached plans in the current database  (Query 38) (Missing Index Warnings)\r\n",
                "-- Note: This query could take some time on a busy instance\r\n",
                "SELECT TOP(25) OBJECT_NAME(objectid) AS [ObjectName], \r\n",
                "               cp.objtype, cp.usecounts, cp.size_in_bytes, qp.query_plan\r\n",
                "FROM sys.dm_exec_cached_plans AS cp WITH (NOLOCK)\r\n",
                "CROSS APPLY sys.dm_exec_query_plan(cp.plan_handle) AS qp\r\n",
                "WHERE CAST(query_plan AS NVARCHAR(MAX)) LIKE N'%MissingIndex%'\r\n",
                "AND dbid = DB_ID()\r\n",
                "ORDER BY cp.usecounts DESC OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "09c74348-103b-49a4-a88a-d9da6ef20045",
                "tags": [
                    "hide_input"
                ]
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "Helps you connect missing indexes to specific stored procedures or queries\r\n",
                "- This can help you decide whether to add them or not"
            ],
            "metadata": {
                "azdata_cell_guid": "8a0cf94b-3603-424b-9015-51215a0c23d9"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Breaks down buffers used by current database by object (table, index) in the buffer cache  (Query 39) (Buffer Usage)"
            ],
            "metadata": {
                "azdata_cell_guid": "b8719781-9935-47fe-9cce-1475fd0c5dde"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Breaks down buffers used by current database by object (table, index) in the buffer cache  (Query 39) (Buffer Usage)\r\n",
                "-- Note: This query could take some time on a busy instance\r\n",
                "SELECT SCHEMA_NAME(o.Schema_ID) AS [Schema Name],\r\n",
                "OBJECT_NAME(p.[object_id]) AS [Object Name], p.index_id, \r\n",
                "CAST(COUNT(*)/128.0 AS DECIMAL(10, 2)) AS [Buffer size(MB)],  \r\n",
                "COUNT(*) AS [BufferCount], p.[Rows] AS [Row Count],\r\n",
                "p.data_compression_desc AS [Compression Type]\r\n",
                "FROM sys.allocation_units AS a WITH (NOLOCK)\r\n",
                "INNER JOIN sys.dm_os_buffer_descriptors AS b WITH (NOLOCK)\r\n",
                "ON a.allocation_unit_id = b.allocation_unit_id\r\n",
                "INNER JOIN sys.partitions AS p WITH (NOLOCK)\r\n",
                "ON a.container_id = p.hobt_id\r\n",
                "INNER JOIN sys.objects AS o WITH (NOLOCK)\r\n",
                "ON p.object_id = o.object_id\r\n",
                "WHERE b.database_id = CONVERT(int, DB_ID())\r\n",
                "AND p.[object_id] > 100\r\n",
                "AND OBJECT_NAME(p.[object_id]) NOT LIKE N'plan_%'\r\n",
                "AND OBJECT_NAME(p.[object_id]) NOT LIKE N'sys%'\r\n",
                "AND OBJECT_NAME(p.[object_id]) NOT LIKE N'xml_index_nodes%'\r\n",
                "GROUP BY o.Schema_ID, p.[object_id], p.index_id, p.data_compression_desc, p.[Rows]\r\n",
                "ORDER BY [BufferCount] DESC OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "e24ea355-502e-4e1a-b17c-1c5e67d930d4",
                "tags": []
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "Tells you what tables and indexes are using the most memory in the buffer cache\r\n",
                "- It can help identify possible candidates for data compression"
            ],
            "metadata": {
                "azdata_cell_guid": "e004de04-81af-4fc4-9bfc-966f8179bd1a"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Get Table names, row counts, and compression status for clustered index or heap  (Query 40) (Table Sizes)"
            ],
            "metadata": {
                "azdata_cell_guid": "0180bfe5-9ef8-4155-95e5-1014e1ba6b2f"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Get Table names, row counts, and compression status for clustered index or heap  (Query 40) (Table Sizes)\r\n",
                "SELECT SCHEMA_NAME(o.Schema_ID) AS [Schema Name], OBJECT_NAME(p.object_id) AS [ObjectName], \r\n",
                "SUM(p.Rows) AS [RowCount], p.data_compression_desc AS [Compression Type]\r\n",
                "FROM sys.partitions AS p WITH (NOLOCK)\r\n",
                "INNER JOIN sys.objects AS o WITH (NOLOCK)\r\n",
                "ON p.object_id = o.object_id\r\n",
                "WHERE index_id < 2 --ignore the partitions from the non-clustered index if any\r\n",
                "AND OBJECT_NAME(p.object_id) NOT LIKE N'sys%'\r\n",
                "AND OBJECT_NAME(p.object_id) NOT LIKE N'spt_%'\r\n",
                "AND OBJECT_NAME(p.object_id) NOT LIKE N'queue_%' \r\n",
                "AND OBJECT_NAME(p.object_id) NOT LIKE N'filestream_tombstone%' \r\n",
                "AND OBJECT_NAME(p.object_id) NOT LIKE N'fulltext%'\r\n",
                "AND OBJECT_NAME(p.object_id) NOT LIKE N'ifts_comp_fragment%'\r\n",
                "AND OBJECT_NAME(p.object_id) NOT LIKE N'filetable_updates%'\r\n",
                "AND OBJECT_NAME(p.object_id) NOT LIKE N'xml_index_nodes%'\r\n",
                "AND OBJECT_NAME(p.object_id) NOT LIKE N'sqlagent_job%'\r\n",
                "AND OBJECT_NAME(p.object_id) NOT LIKE N'plan_persist%'\r\n",
                "GROUP BY  SCHEMA_NAME(o.Schema_ID), p.object_id, data_compression_desc\r\n",
                "ORDER BY SUM(p.Rows) DESC OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "701f9349-8d63-45ec-bdb6-268c38fb52dd",
                "tags": [
                    "hide_input"
                ]
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "Gives you an idea of table sizes, and possible data compression opportunities"
            ],
            "metadata": {
                "azdata_cell_guid": "7d2279f7-f275-4cee-b0ab-4ee8622e6d30"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Get some key table properties (Query 41) (Table Properties)"
            ],
            "metadata": {
                "azdata_cell_guid": "f4afcbe8-bbfe-43c6-b394-5acf2002c590"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Get some key table properties (Query 41) (Table Properties)\r\n",
                "SELECT OBJECT_NAME(t.[object_id]) AS [ObjectName], p.[rows] AS [Table Rows], p.index_id, \r\n",
                "       p.data_compression_desc AS [Index Data Compression],\r\n",
                "       t.create_date, t.lock_on_bulk_load, t.is_replicated, t.has_replication_filter, \r\n",
                "       t.is_tracked_by_cdc, t.lock_escalation_desc, t.is_filetable, \r\n",
                "\t   t.is_memory_optimized, t.durability_desc, \r\n",
                "\t   t.temporal_type_desc, t.is_remote_data_archive_enabled, t.is_external -- new for SQL Server 2016\r\n",
                "FROM sys.tables AS t WITH (NOLOCK)\r\n",
                "INNER JOIN sys.partitions AS p WITH (NOLOCK)\r\n",
                "ON t.[object_id] = p.[object_id]\r\n",
                "WHERE OBJECT_NAME(t.[object_id]) NOT LIKE N'sys%'\r\n",
                "ORDER BY OBJECT_NAME(t.[object_id]), p.index_id OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "0e311d82-931e-4e30-a03c-84973b1e64a2",
                "tags": [
                    "hide_input"
                ]
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "Gives you some good information about your tables\r\n",
                "- is_memory_optimized and durability_desc were new in SQL Server 2014\r\n",
                "- temporal_type_desc, is_remote_data_archive_enabled, is_external were new in SQL Server 2016\r\n",
                "\r\n",
                "[sys.tables (Transact-SQL)](https://bit.ly/2Gk7998)"
            ],
            "metadata": {
                "azdata_cell_guid": "9d9cea25-5540-4d64-bf32-c8efcc2b9560"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## When were Statistics last updated on all indexes?  (Query 42) (Statistics Update)"
            ],
            "metadata": {
                "azdata_cell_guid": "8f276f88-0917-4dfd-b558-362066d8b3af"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- When were Statistics last updated on all indexes?  (Query 42) (Statistics Update)\r\n",
                "SELECT SCHEMA_NAME(o.Schema_ID) + N'.' + o.[NAME] AS [Object Name], o.[type_desc] AS [Object Type],\r\n",
                "      i.[name] AS [Index Name], STATS_DATE(i.[object_id], i.index_id) AS [Statistics Date], \r\n",
                "      s.auto_created, s.no_recompute, s.user_created, s.is_incremental, s.is_temporary,\r\n",
                "\t  st.row_count, st.used_page_count\r\n",
                "FROM sys.objects AS o WITH (NOLOCK)\r\n",
                "INNER JOIN sys.indexes AS i WITH (NOLOCK)\r\n",
                "ON o.[object_id] = i.[object_id]\r\n",
                "INNER JOIN sys.stats AS s WITH (NOLOCK)\r\n",
                "ON i.[object_id] = s.[object_id] \r\n",
                "AND i.index_id = s.stats_id\r\n",
                "INNER JOIN sys.dm_db_partition_stats AS st WITH (NOLOCK)\r\n",
                "ON o.[object_id] = st.[object_id]\r\n",
                "AND i.[index_id] = st.[index_id]\r\n",
                "WHERE o.[type] IN ('U', 'V')\r\n",
                "AND st.row_count > 0\r\n",
                "ORDER BY STATS_DATE(i.[object_id], i.index_id) DESC OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "fe8f81d9-14fe-4c7a-86c4-b3b2b495a368",
                "tags": [
                    "hide_input"
                ]
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "Helps discover possible problems with out-of-date statistics\r\n",
                "- Also gives you an idea which indexes are the most active\r\n",
                "\r\n",
                "[sys.stats (Transact-SQL)](https://bit.ly/2GyAxrn)\r\n",
                "\r\n",
                "[UPDATEs to Statistics (Erin Stellato)](https://bit.ly/2vhrYQy)"
            ],
            "metadata": {
                "azdata_cell_guid": "063735c2-add0-43b4-9bec-2eebbe54a4f7"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Look at most frequently modified indexes and statistics (Query 43) (Volatile Indexes)"
            ],
            "metadata": {
                "azdata_cell_guid": "1c6607f6-bb73-48cd-bd31-3d265f109012"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Look at most frequently modified indexes and statistics (Query 43) (Volatile Indexes)\r\n",
                "SELECT o.[name] AS [Object Name], o.[object_id], o.[type_desc], s.[name] AS [Statistics Name], \r\n",
                "       s.stats_id, s.no_recompute, s.auto_created, s.is_incremental, s.is_temporary,\r\n",
                "\t   sp.modification_counter, sp.[rows], sp.rows_sampled, sp.last_updated\r\n",
                "FROM sys.objects AS o WITH (NOLOCK)\r\n",
                "INNER JOIN sys.stats AS s WITH (NOLOCK)\r\n",
                "ON s.object_id = o.object_id\r\n",
                "CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) AS sp\r\n",
                "WHERE o.[type_desc] NOT IN (N'SYSTEM_TABLE', N'INTERNAL_TABLE')\r\n",
                "AND sp.modification_counter > 0\r\n",
                "ORDER BY sp.modification_counter DESC, o.name OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "a1964ddc-e7a6-42f2-b6d6-b030418c331d",
                "tags": [
                    "hide_input"
                ]
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "This helps you understand your workload and make better decisions about things like data compression and adding new indexes to a table"
            ],
            "metadata": {
                "azdata_cell_guid": "6d8ab598-686e-4a10-9b94-8484328efb20"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Get fragmentation info for all indexes above a certain size in the current database  (Query 44) (Index Fragmentation)"
            ],
            "metadata": {
                "azdata_cell_guid": "9031de0d-fc38-4219-8a88-9728f0ebc79d"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Get fragmentation info for all indexes above a certain size in the current database  (Query 44) (Index Fragmentation)\r\n",
                "-- Note: This query could take some time on a very large database\r\n",
                "SELECT DB_NAME(ps.database_id) AS [Database Name], SCHEMA_NAME(o.[schema_id]) AS [Schema Name],\r\n",
                "OBJECT_NAME(ps.OBJECT_ID) AS [Object Name], i.[name] AS [Index Name], ps.index_id, \r\n",
                "ps.index_type_desc, ps.avg_fragmentation_in_percent, \r\n",
                "ps.fragment_count, ps.page_count, i.fill_factor, i.has_filter, \r\n",
                "i.filter_definition, i.[allow_page_locks]\r\n",
                "FROM sys.dm_db_index_physical_stats(DB_ID(),NULL, NULL, NULL , N'LIMITED') AS ps\r\n",
                "INNER JOIN sys.indexes AS i WITH (NOLOCK)\r\n",
                "ON ps.[object_id] = i.[object_id] \r\n",
                "AND ps.index_id = i.index_id\r\n",
                "INNER JOIN sys.objects AS o WITH (NOLOCK)\r\n",
                "ON i.[object_id] = o.[object_id]\r\n",
                "WHERE ps.database_id = DB_ID()\r\n",
                "AND ps.page_count > 2500\r\n",
                "ORDER BY ps.avg_fragmentation_in_percent DESC OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "6b898df7-b614-4bc5-a032-d475485e7dad",
                "tags": [
                    "hide_input"
                ]
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "Helps determine whether you have framentation in your relational indexes and how effective your index maintenance strategy is.\r\n",
                ""
            ],
            "metadata": {
                "azdata_cell_guid": "fca99494-6705-40ff-9c22-5aa40f158c82"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Index Read/Write stats (all tables in current DB) ordered by Reads  (Query 45) (Overall Index Usage - Reads)"
            ],
            "metadata": {
                "azdata_cell_guid": "1a3ff6ab-165b-411d-8baf-713b6f322dc2"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "--- Index Read/Write stats (all tables in current DB) ordered by Reads  (Query 45) (Overall Index Usage - Reads)\r\n",
                "SELECT OBJECT_NAME(i.[object_id]) AS [ObjectName], i.[name] AS [IndexName], i.index_id, \r\n",
                "       s.user_seeks, s.user_scans, s.user_lookups,\r\n",
                "\t   s.user_seeks + s.user_scans + s.user_lookups AS [Total Reads], \r\n",
                "\t   s.user_updates AS [Writes],  \r\n",
                "\t   i.[type_desc] AS [Index Type], i.fill_factor AS [Fill Factor], i.has_filter, i.filter_definition, \r\n",
                "\t   s.last_user_scan, s.last_user_lookup, s.last_user_seek\r\n",
                "FROM sys.indexes AS i WITH (NOLOCK)\r\n",
                "LEFT OUTER JOIN sys.dm_db_index_usage_stats AS s WITH (NOLOCK)\r\n",
                "ON i.[object_id] = s.[object_id]\r\n",
                "AND i.index_id = s.index_id\r\n",
                "AND s.database_id = DB_ID()\r\n",
                "WHERE OBJECTPROPERTY(i.[object_id],'IsUserTable') = 1\r\n",
                "ORDER BY s.user_seeks + s.user_scans + s.user_lookups DESC OPTION (RECOMPILE); -- Order by reads"
            ],
            "metadata": {
                "azdata_cell_guid": "f2c4b007-fcfb-4e9b-ac40-d7db4caca72f",
                "tags": [
                    "hide_input"
                ]
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "Show which indexes in the current database are most active for Reads"
            ],
            "metadata": {
                "azdata_cell_guid": "3235069d-8003-4494-8145-67cf065d3ee6"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Index Read/Write stats (all tables in current DB) ordered by Writes  (Query 46) (Overall Index Usage - Writes)"
            ],
            "metadata": {
                "azdata_cell_guid": "a3dafd2f-5693-492e-8e7b-f558c4ec624e"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "--- Index Read/Write stats (all tables in current DB) ordered by Writes  (Query 46) (Overall Index Usage - Writes)\r\n",
                "SELECT OBJECT_NAME(i.[object_id]) AS [ObjectName], i.[name] AS [IndexName], i.index_id,\r\n",
                "\t   s.user_updates AS [Writes], s.user_seeks + s.user_scans + s.user_lookups AS [Total Reads], \r\n",
                "\t   i.[type_desc] AS [Index Type], i.fill_factor AS [Fill Factor], i.has_filter, i.filter_definition,\r\n",
                "\t   s.last_system_update, s.last_user_update\r\n",
                "FROM sys.indexes AS i WITH (NOLOCK)\r\n",
                "LEFT OUTER JOIN sys.dm_db_index_usage_stats AS s WITH (NOLOCK)\r\n",
                "ON i.[object_id] = s.[object_id]\r\n",
                "AND i.index_id = s.index_id\r\n",
                "AND s.database_id = DB_ID()\r\n",
                "WHERE OBJECTPROPERTY(i.[object_id],'IsUserTable') = 1\r\n",
                "ORDER BY s.user_updates DESC OPTION (RECOMPILE);\t\t\t\t\t\t -- Order by writes"
            ],
            "metadata": {
                "azdata_cell_guid": "093a4673-62b7-49ec-af4c-8e9568308ddd",
                "tags": [
                    "hide_input"
                ]
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "Show which indexes in the current database are most active for Writes"
            ],
            "metadata": {
                "azdata_cell_guid": "9462fedd-8cc2-48ff-9e59-ec9bb6d0e1e1"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Get in-memory OLTP index usage (Query 47) (XTP Index Usage)"
            ],
            "metadata": {
                "azdata_cell_guid": "7fb895d5-7d7c-49d1-b459-bea8648eee59"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Get in-memory OLTP index usage (Query 47) (XTP Index Usage)\r\n",
                "SELECT OBJECT_NAME(i.[object_id]) AS [Object Name], i.index_id, i.[name] AS [Index Name],\r\n",
                "       i.[type_desc], xis.scans_started, xis.scans_retries, \r\n",
                "\t   xis.rows_touched, xis.rows_returned\r\n",
                "FROM sys.dm_db_xtp_index_stats AS xis WITH (NOLOCK)\r\n",
                "INNER JOIN sys.indexes AS i WITH (NOLOCK)\r\n",
                "ON i.[object_id] = xis.[object_id] \r\n",
                "AND i.index_id = xis.index_id \r\n",
                "ORDER BY OBJECT_NAME(i.[object_id]) OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "b597c25f-b779-4e85-8936-e00ebb16749a",
                "tags": [
                    "hide_input"
                ]
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "This gives you some index usage statistics for in-memory OLTP\r\n",
                "- Returns no data if you are not using in-memory OLTP\r\n",
                "\r\n",
                "[Guidelines for Using Indexes on Memory-Optimized Tables](https://bit.ly/2GCP8lF)"
            ],
            "metadata": {
                "azdata_cell_guid": "aa0d0dc8-bf0d-4e26-bc90-6c9d674600c1"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Look at Columnstore index physical statistics (Query 48) (Columnstore Index Physical Stat)"
            ],
            "metadata": {
                "azdata_cell_guid": "f708aa73-505b-4aaa-9c7a-f1ed5c8b2366"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Look at Columnstore index physical statistics (Query 48) (Columnstore Index Physical Stat)\r\n",
                "SELECT OBJECT_NAME(ps.object_id) AS [TableName],  \r\n",
                "\ti.[name] AS [IndexName], ps.index_id, ps.partition_number,\r\n",
                "\tps.delta_store_hobt_id, ps.state_desc, ps.total_rows, ps.size_in_bytes,\r\n",
                "\tps.trim_reason_desc, ps.generation, ps.transition_to_compressed_state_desc,\r\n",
                "\tps.has_vertipaq_optimization, ps.deleted_rows,\r\n",
                "\t100 * (ISNULL(ps.deleted_rows, 0))/ps.total_rows AS [Fragmentation]\r\n",
                "FROM sys.dm_db_column_store_row_group_physical_stats AS ps WITH (NOLOCK)\r\n",
                "INNER JOIN sys.indexes AS i WITH (NOLOCK)\r\n",
                "ON ps.object_id = i.object_id \r\n",
                "AND ps.index_id = i.index_id\r\n",
                "ORDER BY ps.object_id, ps.partition_number, ps.row_group_id OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "08085237-8152-4c51-b600-7325b1a3548c",
                "tags": [
                    "hide_input"
                ]
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "[sys.dm_db_column_store_row_group_physical_stats (Transact-SQL)](https://bit.ly/2q276XQ)"
            ],
            "metadata": {
                "azdata_cell_guid": "1220c55f-75d8-40d7-bf05-69b75801620c"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Get lock waits for current database (Query 49) (Lock Waits)"
            ],
            "metadata": {
                "azdata_cell_guid": "58df2dd4-b3ff-4947-9cef-407ff9d74ca2"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Get lock waits for current database (Query 49) (Lock Waits)\r\n",
                "SELECT o.name AS [table_name], i.name AS [index_name], ios.index_id, ios.partition_number,\r\n",
                "\t\tSUM(ios.row_lock_wait_count) AS [total_row_lock_waits], \r\n",
                "\t\tSUM(ios.row_lock_wait_in_ms) AS [total_row_lock_wait_in_ms],\r\n",
                "\t\tSUM(ios.page_lock_wait_count) AS [total_page_lock_waits],\r\n",
                "\t\tSUM(ios.page_lock_wait_in_ms) AS [total_page_lock_wait_in_ms],\r\n",
                "\t\tSUM(ios.page_lock_wait_in_ms)+ SUM(row_lock_wait_in_ms) AS [total_lock_wait_in_ms]\r\n",
                "FROM sys.dm_db_index_operational_stats(DB_ID(), NULL, NULL, NULL) AS ios\r\n",
                "INNER JOIN sys.objects AS o WITH (NOLOCK)\r\n",
                "ON ios.[object_id] = o.[object_id]\r\n",
                "INNER JOIN sys.indexes AS i WITH (NOLOCK)\r\n",
                "ON ios.[object_id] = i.[object_id] \r\n",
                "AND ios.index_id = i.index_id\r\n",
                "WHERE o.[object_id] > 100\r\n",
                "GROUP BY o.name, i.name, ios.index_id, ios.partition_number\r\n",
                "HAVING SUM(ios.page_lock_wait_in_ms)+ SUM(row_lock_wait_in_ms) > 0\r\n",
                "ORDER BY total_lock_wait_in_ms DESC OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "8838a469-4f87-4a8f-9673-6536829258e3",
                "tags": [
                    "hide_input"
                ]
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "This query is helpful for troubleshooting blocking and deadlocking issues"
            ],
            "metadata": {
                "azdata_cell_guid": "e33db965-e46a-4087-b9c9-9ad72b713c03"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Look at UDF execution statistics (Query 50) (UDF Statistics)"
            ],
            "metadata": {
                "azdata_cell_guid": "4bc1f2be-a361-4e8c-a11f-43a8b9d31278"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Look at UDF execution statistics (Query 50) (UDF Statistics)\r\n",
                "SELECT OBJECT_NAME(object_id) AS [Function Name], execution_count,\r\n",
                "\t   total_worker_time, total_logical_reads, total_physical_reads, total_elapsed_time, \r\n",
                "\t   total_elapsed_time/execution_count AS [avg_elapsed_time],\r\n",
                "\t   FORMAT(cached_time, 'yyyy-MM-dd HH:mm:ss', 'en-US') AS [Plan Cached Time]\r\n",
                "FROM sys.dm_exec_function_stats WITH (NOLOCK) \r\n",
                "WHERE database_id = DB_ID()\r\n",
                "ORDER BY total_worker_time DESC OPTION (RECOMPILE); "
            ],
            "metadata": {
                "azdata_cell_guid": "ba01047c-7f3d-4458-9c59-1d9e6a61dd14",
                "tags": [
                    "hide_input"
                ]
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "New for SQL Server 2016\r\n",
                "- Helps you investigate scalar UDF performance issues\r\n",
                "- Does not return information for table valued functions\r\n",
                "\r\n",
                "[sys.dm_exec_function_stats (Transact-SQL)](https://bit.ly/2q1Q6BM)"
            ],
            "metadata": {
                "azdata_cell_guid": "cd874542-572c-43a6-824f-705362654485"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Get QueryStore Options for this database (Query 51) (QueryStore Options)"
            ],
            "metadata": {
                "azdata_cell_guid": "04fecb8a-6fa8-4aae-9cc0-22f4aa0419e4"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Get QueryStore Options for this database (Query 51) (QueryStore Options)\r\n",
                "SELECT actual_state_desc, desired_state_desc, [interval_length_minutes],\r\n",
                "       current_storage_size_mb, [max_storage_size_mb], \r\n",
                "\t   query_capture_mode_desc, size_based_cleanup_mode_desc\r\n",
                "FROM sys.database_query_store_options WITH (NOLOCK) OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "fbfb5d86-cd44-49e3-9a63-12be523945d4",
                "tags": [
                    "hide_input"
                ]
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "New for SQL Server 2016\r\n",
                "- Requires that Query Store is enabled for this database\r\n",
                "- Make sure that the actual_state_desc is the same as desired_state_desc\r\n",
                "- Make sure that the current_storage_size_mb is less than the max_storage_size_mb\r\n",
                "\r\n",
                "[Tuning Workload Performance with Query Store](https://bit.ly/1kHSl7w)"
            ],
            "metadata": {
                "azdata_cell_guid": "43d3591d-de83-4648-897b-17916dd22574"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Get highest aggregate duration queries over last hour (Query 52) (High Aggregate Duration Queries)"
            ],
            "metadata": {
                "azdata_cell_guid": "1154a41b-168d-47cc-aea7-513fc6a31f6a"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Get highest aggregate duration queries over last hour (Query 52) (High Aggregate Duration Queries)\r\n",
                "WITH AggregatedDurationLastHour\r\n",
                "AS\r\n",
                "(SELECT q.query_id, SUM(count_executions * avg_duration) AS total_duration,\r\n",
                "   COUNT (distinct p.plan_id) AS number_of_plans\r\n",
                "   FROM sys.query_store_query_text AS qt WITH (NOLOCK)\r\n",
                "   INNER JOIN sys.query_store_query AS q WITH (NOLOCK)\r\n",
                "   ON qt.query_text_id = q.query_text_id\r\n",
                "   INNER JOIN sys.query_store_plan AS p WITH (NOLOCK)\r\n",
                "   ON q.query_id = p.query_id\r\n",
                "   INNER JOIN sys.query_store_runtime_stats AS rs WITH (NOLOCK)\r\n",
                "   ON rs.plan_id = p.plan_id\r\n",
                "   INNER JOIN sys.query_store_runtime_stats_interval AS rsi WITH (NOLOCK)\r\n",
                "   ON rsi.runtime_stats_interval_id = rs.runtime_stats_interval_id\r\n",
                "   WHERE rsi.start_time >= DATEADD(hour, -1, GETUTCDATE()) \r\n",
                "   AND rs.execution_type_desc = N'Regular'\r\n",
                "   GROUP BY q.query_id),\r\n",
                "OrderedDuration AS\r\n",
                "(SELECT query_id, total_duration, number_of_plans, \r\n",
                " ROW_NUMBER () OVER (ORDER BY total_duration DESC, query_id) AS RN\r\n",
                " FROM AggregatedDurationLastHour)\r\n",
                "SELECT OBJECT_NAME(q.object_id) AS [Containing Object], qt.query_sql_text, \r\n",
                "od.total_duration AS [Total Duration (microsecs)], \r\n",
                "od.number_of_plans AS [Plan Count],\r\n",
                "p.is_forced_plan, p.is_parallel_plan, p.is_trivial_plan,\r\n",
                "q.query_parameterization_type_desc, p.[compatibility_level],\r\n",
                "p.last_compile_start_time, q.last_execution_time,\r\n",
                "CONVERT(xml, p.query_plan) AS query_plan_xml \r\n",
                "FROM OrderedDuration AS od \r\n",
                "INNER JOIN sys.query_store_query AS q WITH (NOLOCK)\r\n",
                "ON q.query_id  = od.query_id\r\n",
                "INNER JOIN sys.query_store_query_text AS qt WITH (NOLOCK)\r\n",
                "ON q.query_text_id = qt.query_text_id\r\n",
                "INNER JOIN sys.query_store_plan AS p WITH (NOLOCK)\r\n",
                "ON q.query_id = p.query_id\r\n",
                "WHERE od.RN <= 50 \r\n",
                "ORDER BY total_duration DESC OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "77985c35-00ed-4e6f-a603-81e61c009f65",
                "tags": [
                    "hide_input"
                ]
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "- New for SQL Server 2016\r\n",
                "- Requires that QueryStore is enabled for this database"
            ],
            "metadata": {
                "azdata_cell_guid": "c0ec9628-0a35-41d6-8c9c-4fb4dfb50ebf"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Get input buffer information for the current database (Query 53) (Input Buffer)"
            ],
            "metadata": {
                "azdata_cell_guid": "414cd580-c270-4284-a0e9-dc913d5003d3"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Get input buffer information for the current database (Query 53) (Input Buffer)\r\n",
                "SELECT es.session_id, DB_NAME(es.database_id) AS [Database Name],\r\n",
                "       es.login_time, es.cpu_time, es.logical_reads, es.memory_usage,\r\n",
                "       es.[status], ib.event_info AS [Input Buffer]\r\n",
                "FROM sys.dm_exec_sessions AS es WITH (NOLOCK)\r\n",
                "CROSS APPLY sys.dm_exec_input_buffer(es.session_id, NULL) AS ib\r\n",
                "WHERE es.database_id = DB_ID()\r\n",
                "AND es.session_id > 50\r\n",
                "AND es.session_id <> @@SPID OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "61079c9c-041c-4dfa-8fe2-962241c7078e",
                "tags": [
                    "hide_input"
                ]
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "Gives you input buffer information from all non-system sessions for the current database\r\n",
                "- Replaces `DBCC INPUTBUFFER`\r\n",
                "\r\n",
                "[New DMF for retrieving input buffer in SQL Serve](https://bit.ly/2uHKMbz)r\r\n",
                "\r\n",
                "[sys.dm_exec_input_buffer (Transact-SQL)](https://bit.ly/2J5Hf9q)"
            ],
            "metadata": {
                "azdata_cell_guid": "8fa0e32e-b2f1-43de-9d7c-a516800ebdcf"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Get any resumable index rebuild operation information (Query 54) (Resumable Index Rebuild)"
            ],
            "metadata": {
                "azdata_cell_guid": "db25476b-da67-4b59-accb-1d426a1bfa5d"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Get any resumable index rebuild operation information (Query 54) (Resumable Index Rebuild)\r\n",
                "SELECT OBJECT_NAME(iro.object_id) AS [Object Name], iro.index_id, iro.name AS [Index Name],\r\n",
                "       iro.sql_text, iro.last_max_dop_used, iro.partition_number, iro.state_desc, iro.start_time, iro.percent_complete\r\n",
                "FROM  sys.index_resumable_operations AS iro WITH (NOLOCK)\r\n",
                "OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "70c40dd2-a2e3-49a9-99cc-d79cb62a0ff2",
                "tags": [
                    "hide_input"
                ]
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "[index_resumable_operations (Transact-SQL)](https://bit.ly/2pYSWqq)"
            ],
            "metadata": {
                "azdata_cell_guid": "6a575977-fbe5-45b7-9849-8e22bcdc91a6"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Get database automatic tuning options (Query 55) (Automatic Tuning Options)"
            ],
            "metadata": {
                "azdata_cell_guid": "5b5aa22a-ec08-4883-9ba3-5b493dcfad62"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Get database automatic tuning options (Query 55) (Automatic Tuning Options)\r\n",
                "SELECT [name], desired_state_desc, actual_state_desc, reason_desc\r\n",
                "FROM sys.database_automatic_tuning_options WITH (NOLOCK)\r\n",
                "OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "92e12733-6eab-464e-bad6-8e193a5bb024",
                "tags": [
                    "hide_input"
                ]
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "[sys.database_automatic_tuning_options (Transact-SQL)](https://bit.ly/2FHhLkL)"
            ],
            "metadata": {
                "azdata_cell_guid": "0739c550-fd16-4268-9146-858c7d33ab84"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Get geo-replication link status for all secondary databases (Query 56) (Geo-Replication Link Status)"
            ],
            "metadata": {
                "azdata_cell_guid": "d419108a-d2fc-41a7-9524-6c42038ab4a8"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Get geo-replication link status for all secondary databases (Query 56) (Geo-Replication Link Status)\r\n",
                "SELECT link_guid, partner_server, partner_database, last_replication, \r\n",
                "       replication_lag_sec, replication_state_desc, role_desc, secondary_allow_connections_desc \r\n",
                "FROM sys.dm_geo_replication_link_status WITH (NOLOCK) OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "36537d06-fc40-4acc-a5db-62244c742a73",
                "tags": [
                    "hide_input"
                ]
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "[sys.dm_geo_replication_link_status (Azure SQL Database)](https://bit.ly/2GwIqC2)"
            ],
            "metadata": {
                "azdata_cell_guid": "e79226b5-b0d8-47e8-a6dc-e60c3b775605"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Retrieve some Azure SQL Database properties (Query 57) (Azure SQL DB Properties)"
            ],
            "metadata": {
                "azdata_cell_guid": "c6705624-b8e9-4015-89dd-df10814b2591"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Retrieve some Azure SQL Database properties (Query 57) (Azure SQL DB Properties)\r\n",
                "SELECT DATABASEPROPERTYEX (DB_NAME(DB_ID()), 'Edition') AS [Database Edition],\r\n",
                "\t   DATABASEPROPERTYEX (DB_NAME(DB_ID()), 'ServiceObjective') AS [Service Objective],\r\n",
                "\t   DATABASEPROPERTYEX (DB_NAME(DB_ID()), 'MaxSizeInBytes') AS [Max Size In Bytes],\r\n",
                "\t   DATABASEPROPERTYEX (DB_NAME(DB_ID()), 'IsXTPSupported') AS [Is XTP Supported]\r\n",
                "\t   OPTION (RECOMPILE);   "
            ],
            "metadata": {
                "azdata_cell_guid": "2975ca3e-c10a-425b-aebc-3db37f38855c",
                "tags": [
                    "hide_input"
                ]
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "# Appendix\r\n",
                "\r\n",
                "**These six Pluralsight Courses go into more detail about how to run these queries and interpret the results**\r\n",
                "\r\n",
                "- [Azure SQL Database: Diagnosing Performance Issues with DMVs](https://bit.ly/2meDRCN)\r\n",
                "- [SQL Server 2017: Diagnosing Performance Issues with DMVs](https://bit.ly/2FqCeti)\r\n",
                "- [SQL Server 2017: Diagnosing Configuration Issues with DMVs](https://bit.ly/2MSUDUL)\r\n",
                "- [SQL Server 2014 DMV Diagnostic Queries – Part 1](https://bit.ly/2plxCer) \r\n",
                "- [SQL Server 2014 DMV Diagnostic Queries – Part 2](https://bit.ly/2IuJpzI)\r\n",
                "- [SQL Server 2014 DMV Diagnostic Queries – Part 3](https://bit.ly/2FIlCPb)\r\n",
                "\r\n",
                "\r\n",
                "\r\n",
                "\r\n",
                "[Microsoft Visual Studio Dev Essentials](https://bit.ly/2qjNRxi)\r\n",
                "\r\n",
                "[Microsoft Azure Learn](https://bit.ly/2O0Hacc)"
            ],
            "metadata": {
                "azdata_cell_guid": "e0569096-089f-44d7-99cb-9adaf1e3e8e7"
            }
        }
    ]
}