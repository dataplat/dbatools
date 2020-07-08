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
                "# **SQL Server 2017 Diagnostic Information Queries**\r\n",
                "- Glenn Berry \r\n",
                "- Last Modified: July 3, 2020\r\n",
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
                "# Instance-Level Queries\r\n",
                "\r\n",
                "For these queries, it doesn't matter which database you are connected to"
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
                "* [SQL Server 2017 build versions](https://bit.ly/2FLY88I)\r\n",
                "* [Download and install Azure Data Studio](https://bit.ly/2vgke1A)"
            ],
            "metadata": {
                "azdata_cell_guid": "c67f68fc-4b1a-41b5-968c-80ef608bf9b3"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Get socket, physical core and logical core count from the SQL Server Error log. (Query 2) (Core Counts)"
            ],
            "metadata": {
                "azdata_cell_guid": "77f88c89-ed5e-4e85-b862-3c0de145bc42"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Get socket, physical core and logical core count from the SQL Server Error log. (Query 2) (Core Counts)\r\n",
                "-- This query might take a few seconds depending on the size of your error log\r\n",
                "EXEC sys.xp_readerrorlog 0, 1, N'detected', N'socket';"
            ],
            "metadata": {
                "azdata_cell_guid": "671b21d0-7cd1-48df-b99b-2a0fbd896519",
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
                "- This can help you determine the exact core counts used by SQL Server and whether HT is enabled or not\r\n",
                "- It can also help you confirm your SQL Server licensing model\r\n",
                "- Be on the lookout for this message \"using 40 logical processors based on SQL Server licensing\" (when you have more than 40 logical cores) which means grandfathered Server/CAL licensing\r\n",
                "- This query will return no results if your error log has been recycled since the instance was last started\r\n",
                ""
            ],
            "metadata": {
                "azdata_cell_guid": "2f2f4bdf-13cc-4e6d-afd8-41e66e7b662e"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Get selected server properties (Query 3) (Server Properties)"
            ],
            "metadata": {
                "azdata_cell_guid": "be88592b-4048-4079-95ae-5cdf4dc3d565"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Get selected server properties (Query 3) (Server Properties)\r\n",
                "SELECT SERVERPROPERTY('MachineName') AS [MachineName], \r\n",
                "SERVERPROPERTY('ServerName') AS [ServerName],  \r\n",
                "SERVERPROPERTY('InstanceName') AS [Instance], \r\n",
                "SERVERPROPERTY('IsClustered') AS [IsClustered], \r\n",
                "SERVERPROPERTY('ComputerNamePhysicalNetBIOS') AS [ComputerNamePhysicalNetBIOS], \r\n",
                "SERVERPROPERTY('Edition') AS [Edition], \r\n",
                "SERVERPROPERTY('ProductLevel') AS [ProductLevel],\t\t\t\t-- What servicing branch (RTM/SP/CU)\r\n",
                "SERVERPROPERTY('ProductUpdateLevel') AS [ProductUpdateLevel],\t-- Within a servicing branch, what CU# is applied\r\n",
                "SERVERPROPERTY('ProductVersion') AS [ProductVersion],\r\n",
                "SERVERPROPERTY('ProductMajorVersion') AS [ProductMajorVersion], \r\n",
                "SERVERPROPERTY('ProductMinorVersion') AS [ProductMinorVersion], \r\n",
                "SERVERPROPERTY('ProductBuild') AS [ProductBuild], \r\n",
                "SERVERPROPERTY('ProductBuildType') AS [ProductBuildType],\t\t\t  -- Is this a GDR or OD hotfix (NULL if on a CU build)\r\n",
                "SERVERPROPERTY('ProductUpdateReference') AS [ProductUpdateReference], -- KB article number that is applicable for this build\r\n",
                "SERVERPROPERTY('ProcessID') AS [ProcessID],\r\n",
                "SERVERPROPERTY('Collation') AS [Collation], \r\n",
                "SERVERPROPERTY('IsFullTextInstalled') AS [IsFullTextInstalled], \r\n",
                "SERVERPROPERTY('IsIntegratedSecurityOnly') AS [IsIntegratedSecurityOnly],\r\n",
                "SERVERPROPERTY('FilestreamConfiguredLevel') AS [FilestreamConfiguredLevel],\r\n",
                "SERVERPROPERTY('IsHadrEnabled') AS [IsHadrEnabled], \r\n",
                "SERVERPROPERTY('HadrManagerStatus') AS [HadrManagerStatus],\r\n",
                "SERVERPROPERTY('InstanceDefaultDataPath') AS [InstanceDefaultDataPath],\r\n",
                "SERVERPROPERTY('InstanceDefaultLogPath') AS [InstanceDefaultLogPath],\r\n",
                "SERVERPROPERTY('BuildClrVersion') AS [Build CLR Version],\r\n",
                "SERVERPROPERTY('IsXTPSupported') AS [IsXTPSupported],\r\n",
                "SERVERPROPERTY('IsPolybaseInstalled') AS [IsPolybaseInstalled],\t\t\t\t\r\n",
                "SERVERPROPERTY('IsAdvancedAnalyticsInstalled') AS [IsRServicesInstalled];"
            ],
            "metadata": {
                "azdata_cell_guid": "fd8bc7f4-b027-4ce3-9adc-a05d7feb7988",
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
                "This gives you a lot of useful information about your instance of SQL Server,\r\n",
                "such as the ProcessID for SQL Server and your collation\r\n",
                "> **Note:** Some columns will be NULL on older SQL Server builds\r\n",
                "\r\n",
                "`SERVERPROPERTY('IsTempdbMetadataMemoryOptimized')` is a new option for SQL Server 2019\r\n",
                "\r\n",
                "[SERVERPROPERTY (Transact-SQL)](https://bit.ly/2eeaXeI)\r\n",
                ""
            ],
            "metadata": {
                "azdata_cell_guid": "43366523-0a80-4f61-87c4-17aa7c38371e"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Get instance-level configuration values for instance  (Query 4) (Configuration Values)"
            ],
            "metadata": {
                "azdata_cell_guid": "6f4b2c84-abac-4e11-b736-8fc4b56cd4ed"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Get instance-level configuration values for instance  (Query 4) (Configuration Values)\r\n",
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
                "**Focus on these settings:**\r\n",
                "- automatic soft-NUMA disabled (should be 0 in most cases)\r\n",
                "- backup checksum default (should be 1)\r\n",
                "- backup compression default (should be 1 in most cases)\r\n",
                "- clr enabled (only enable if it is needed)\r\n",
                "- cost threshold for parallelism (depends on your workload)\r\n",
                "- lightweight pooling (should be zero)\r\n",
                "- max degree of parallelism (depends on your workload and hardware)\r\n",
                "- max server memory (MB) (set to an appropriate value, not the default)\r\n",
                "- optimize for ad hoc workloads (should be 1)\r\n",
                "- priority boost (should be zero)\r\n",
                "- remote admin connections (should be 1)\r\n",
                "\r\n",
                "[sys.configurations (Transact-SQL)](https://bit.ly/2HsyDZI)"
            ],
            "metadata": {
                "azdata_cell_guid": "1b2643f1-a51f-4979-bfd5-a4aeb0f2c64e"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Returns a list of all global trace flags that are enabled (Query 5) (Global Trace Flags)"
            ],
            "metadata": {
                "azdata_cell_guid": "178870c8-dd17-4674-9695-e0db5a6888a8"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Returns a list of all global trace flags that are enabled (Query 5) (Global Trace Flags)\r\n",
                "DBCC TRACESTATUS (-1);"
            ],
            "metadata": {
                "azdata_cell_guid": "8826e766-feea-48b3-9c92-6e0dfac14752",
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
                "If no global trace flags are enabled, no results will be returned.\r\n",
                "It is very useful to know what global trace flags are currently enabled as part of the diagnostic process.\r\n",
                "\r\n",
                "Common trace flags that should be enabled in most cases:\r\n",
                "\r\n",
                "- **TF 460**  - [Improvement: Optional replacement for \"String or binary data would be truncated\" message with extended information in SQL Server 2017](https://bit.ly/2sboMli)\r\n",
                "- **TF 3226** - [Supresses logging of successful database backup messages to the SQL Server Error Log](https://bit.ly/38zDNAK )\r\n",
                "- **TF 6534** - [Enables use of native code to improve performance with spatial data](https://bit.ly/2HrQUpU)       \r\n",
                "- **TF 7745** - [Prevents Query Store data from being written to disk in case of a failover or shutdown command](https://bit.ly/2GU69Km)\r\n",
                "- **TF 7752** - [Enables asynchronous load of Query Store](https://bit.ly/2GU69Km)\r\n",
                "\r\n",
                "[DBCC TRACEON - Trace Flags (Transact-SQL)](https://bit.ly/2FuSvPg)\r\n",
                "\r\n",
                "[Recommended updates and configuration options for SQL Server 2017 and 2016 with high-performance workloads](https://bit.ly/2VVRGTY)"
            ],
            "metadata": {
                "azdata_cell_guid": "141c6882-a3ce-4ec9-a132-6b2c8143b336"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## SQL Server Process Address space info  (Query 6) (Process Memory)"
            ],
            "metadata": {
                "azdata_cell_guid": "dd724a46-dfcc-4dcc-8cd7-b22b2a746688"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- SQL Server Process Address space info  (Query 6) (Process Memory)\r\n",
                "-- (shows whether locked pages is enabled, among other things)\r\n",
                "SELECT physical_memory_in_use_kb/1024 AS [SQL Server Memory Usage (MB)],\r\n",
                "\t   locked_page_allocations_kb/1024 AS [SQL Server Locked Pages Allocation (MB)],\r\n",
                "       large_page_allocations_kb/1024 AS [SQL Server Large Pages Allocation (MB)], \r\n",
                "\t   page_fault_count, memory_utilization_percentage, available_commit_limit_kb, \r\n",
                "\t   process_physical_memory_low, process_virtual_memory_low\r\n",
                "FROM sys.dm_os_process_memory WITH (NOLOCK) OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "110d67ad-134b-4e9b-8761-d43f68ccda2a",
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
                "- You want to see 0 for process_physical_memory_low\r\n",
                "- You want to see 0 for process_virtual_memory_low\r\n",
                "\r\n",
                "This indicates that you are not under internal memory pressure.\r\n",
                "If locked_page_allocations_kb > 0, then LPIM is enabled\r\n",
                "\r\n",
                "[How to enable the \"locked pages\" feature in SQL Server 2012](https://bit.ly/2F5UjOA)\r\n",
                "\r\n",
                "[Memory Management Architecture Guide](https://bit.ly/2JKkadC)"
            ],
            "metadata": {
                "azdata_cell_guid": "3c643dfe-9727-4d52-9f78-c94088e05c2b"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## SQL Server Services information (Query 7) (SQL Server Services Info)"
            ],
            "metadata": {
                "azdata_cell_guid": "813d193b-0730-4aaa-a1fa-2b1b272da7fb"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- SQL Server Services information (Query 7) (SQL Server Services Info)\r\n",
                "SELECT servicename, process_id, startup_type_desc, status_desc, \r\n",
                "last_startup_time, service_account, is_clustered, cluster_nodename, [filename], \r\n",
                "instant_file_initialization_enabled\r\n",
                "FROM sys.dm_server_services WITH (NOLOCK) OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "35356285-db3b-414b-9cb3-9441b692044a",
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
                "- Tells you the account being used for the SQL Server Service and the SQL Agent Service\r\n",
                "- Shows the process_id, when they were last started, and their current status\r\n",
                "- Also shows whether you are running on a failover cluster instance, and what node you are running on\r\n",
                "- Also shows whether IFI is enabled\r\n",
                "\r\n",
                "[sys.dm_server_services (Transact-SQL)](https://bit.ly/2oKa1Un)"
            ],
            "metadata": {
                "azdata_cell_guid": "94a924e0-dffa-409e-ab52-033d687807ba"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Last backup information by database  (Query 8) (Last Backup By Database)"
            ],
            "metadata": {
                "azdata_cell_guid": "6e2d2211-2025-418c-89ac-99ada11f122e"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Last backup information by database  (Query 8) (Last Backup By Database)\r\n",
                "SELECT ISNULL(d.[name], bs.[database_name]) AS [Database], d.recovery_model_desc AS [Recovery Model], \r\n",
                "       d.log_reuse_wait_desc AS [Log Reuse Wait Desc],\r\n",
                "    MAX(CASE WHEN [type] = 'D' THEN bs.backup_finish_date ELSE NULL END) AS [Last Full Backup],\r\n",
                "    MAX(CASE WHEN [type] = 'I' THEN bs.backup_finish_date ELSE NULL END) AS [Last Differential Backup],\r\n",
                "    MAX(CASE WHEN [type] = 'L' THEN bs.backup_finish_date ELSE NULL END) AS [Last Log Backup]\r\n",
                "FROM sys.databases AS d WITH (NOLOCK)\r\n",
                "LEFT OUTER JOIN msdb.dbo.backupset AS bs WITH (NOLOCK)\r\n",
                "ON bs.[database_name] = d.[name] \r\n",
                "AND bs.backup_finish_date > GETDATE()- 30\r\n",
                "WHERE d.name <> N'tempdb'\r\n",
                "GROUP BY ISNULL(d.[name], bs.[database_name]), d.recovery_model_desc, d.log_reuse_wait_desc, d.[name] \r\n",
                "ORDER BY d.recovery_model_desc, d.[name] OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "3f0b33ef-048e-4791-8b22-e097413a971d",
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
                "This helps you spot runaway transaction logs and other issues with your backup schedule"
            ],
            "metadata": {
                "azdata_cell_guid": "2c03ed0a-4f62-4087-a87d-4ab6039fbc36"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Get SQL Server Agent jobs and Category information (Query 9) (SQL Server Agent Jobs)"
            ],
            "metadata": {
                "azdata_cell_guid": "29ee78b2-aea2-437c-b74c-e25e18a21d85"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Get SQL Server Agent jobs and Category information (Query 9) (SQL Server Agent Jobs)\r\n",
                "SELECT sj.name AS [Job Name], sj.[description] AS [Job Description], SUSER_SNAME(sj.owner_sid) AS [Job Owner],\r\n",
                "sj.date_created AS [Date Created], sj.[enabled] AS [Job Enabled], \r\n",
                "sj.notify_email_operator_id, sj.notify_level_email, sc.name AS [CategoryName],\r\n",
                "s.[enabled] AS [Sched Enabled], js.next_run_date, js.next_run_time\r\n",
                "FROM msdb.dbo.sysjobs AS sj WITH (NOLOCK)\r\n",
                "INNER JOIN msdb.dbo.syscategories AS sc WITH (NOLOCK)\r\n",
                "ON sj.category_id = sc.category_id\r\n",
                "LEFT OUTER JOIN msdb.dbo.sysjobschedules AS js WITH (NOLOCK)\r\n",
                "ON sj.job_id = js.job_id\r\n",
                "LEFT OUTER JOIN msdb.dbo.sysschedules AS s WITH (NOLOCK)\r\n",
                "ON js.schedule_id = s.schedule_id\r\n",
                "ORDER BY sj.name OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "a2ca93cb-1cc4-4179-8c93-d58fe12d1649",
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
                "Gives you some basic information about your SQL Server Agent jobs, who owns them and how they are configured\r\n",
                "\r\n",
                "- Look for Agent jobs that are not owned by sa\r\n",
                "- Look for jobs that have a notify_email_operator_id set to 0 (meaning no operator)\r\n",
                "- Look for jobs that have a notify_level_email set to 0 (meaning no e-mail is ever sent)\r\n",
                "\r\n",
                "[MSDN sysjobs documentation](https://bit.ly/2paDEOP)\r\n",
                "\r\n",
                "[SQL Server Maintenance Solution- Ola Hallengren](https://bit.ly/1pgchQu)\r\n",
                "\r\n",
                "[You can use this script to add default schedules to the standard Ola Hallengren Maintenance Solution jobs](https://bit.ly/3ane0gN)\r\n",
                ""
            ],
            "metadata": {
                "azdata_cell_guid": "2f4e2b5a-5996-48c5-bfff-212aa70309bc"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Get SQL Server Agent Alert Information (Query 10) (SQL Server Agent Alerts)"
            ],
            "metadata": {
                "azdata_cell_guid": "573ded7e-e88d-4f22-acaf-fbc7d50f5cc2"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Get SQL Server Agent Alert Information (Query 10) (SQL Server Agent Alerts)\r\n",
                "SELECT name, event_source, message_id, severity, [enabled], has_notification, \r\n",
                "       delay_between_responses, occurrence_count, last_occurrence_date, last_occurrence_time\r\n",
                "FROM msdb.dbo.sysalerts WITH (NOLOCK)\r\n",
                "ORDER BY name OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "9a9e4054-4adc-4b2e-af9f-47bd06526d2f",
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
                "Gives you some basic information about your SQL Server Agent Alerts, which are different from SQL Server Agent jobs\r\n",
                "- Read more about Agent Alerts [here](https://bit.ly/2v5YR37) "
            ],
            "metadata": {
                "azdata_cell_guid": "e049ee36-1dba-4e9a-80e0-eed34733ed98"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Host information (Query 11) (Host Info)"
            ],
            "metadata": {
                "azdata_cell_guid": "7ceed0ca-74fe-4001-a142-2aaf6477c75d"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Host information (Query 11) (Host Info)\r\n",
                "SELECT host_platform, host_distribution, host_release, \r\n",
                "       host_service_pack_level, host_sku, os_language_version \r\n",
                "FROM sys.dm_os_host_info WITH (NOLOCK) OPTION (RECOMPILE); "
            ],
            "metadata": {
                "azdata_cell_guid": "44e4b7bb-0cef-4d2a-a70e-0a325946e003",
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
                "[Hardware and Software Requirements for Installing SQL Server](https://bit.ly/2y3ka5L)"
            ],
            "metadata": {
                "azdata_cell_guid": "2fc1319b-b067-4a6a-85bb-3da123585959"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## SQL Server NUMA Node information  (Query 12) (SQL Server NUMA Info)"
            ],
            "metadata": {
                "azdata_cell_guid": "41af2734-b348-4d22-9c56-a9a5680c4df9"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- SQL Server NUMA Node information  (Query 12) (SQL Server NUMA Info)\r\n",
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
                "- Watch out if SQL Server 2017 Standard Edition has been installed on a physical or virtual machine with more than four sockets or more than 24 physical cores\r\n",
                "\r\n",
                "[sys.dm_os_nodes (Transact-SQL)](https://bit.ly/2pn5Mw8)\r\n",
                "\r\n",
                "[How to Balance SQL Server Core Licenses Across NUMA Nodes](https://bit.ly/3i4TyVR)"
            ],
            "metadata": {
                "azdata_cell_guid": "510439a6-15ab-4097-beb9-cb32368ee294"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Good basic information about OS memory amounts and state  (Query 13) (System Memory)"
            ],
            "metadata": {
                "azdata_cell_guid": "f9868d6a-c014-434b-8826-6509aeb88db5"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Good basic information about OS memory amounts and state  (Query 13) (System Memory)\r\n",
                "SELECT total_physical_memory_kb/1024 AS [Physical Memory (MB)], \r\n",
                "       available_physical_memory_kb/1024 AS [Available Memory (MB)], \r\n",
                "       total_page_file_kb/1024 AS [Page File Commit Limit (MB)],\r\n",
                "\t   total_page_file_kb/1024 - total_physical_memory_kb/1024 AS [Physical Page File Size (MB)],\r\n",
                "\t   available_page_file_kb/1024 AS [Available Page File (MB)], \r\n",
                "\t   system_cache_kb/1024 AS [System Cache (MB)],\r\n",
                "       system_memory_state_desc AS [System Memory State]\r\n",
                "FROM sys.dm_os_sys_memory WITH (NOLOCK) OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "e510dc91-ef2c-430b-bcac-7af40a9251cf",
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
                "You want to see \"Available physical memory is high\" for System Memory State. This indicates that you are not under external memory pressure\r\n",
                "\r\n",
                "Possible System Memory State values:\r\n",
                "- Available physical memory is high\r\n",
                "- Physical memory usage is steady\r\n",
                "- Available physical memory is low\r\n",
                "- Available physical memory is running low\r\n",
                "- Physical memory state is transitioning\r\n",
                "\r\n",
                "[sys.dm_os_sys_memory (Transact-SQL)](https://bit.ly/2pcV0xq)"
            ],
            "metadata": {
                "azdata_cell_guid": "1f866346-3979-40e6-bc55-8f21a6f7318e"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "> **You can skip the next three queries if you know you don't have a clustered instance**"
            ],
            "metadata": {
                "azdata_cell_guid": "83e88f2b-4f2f-42f0-8294-3fc0bab5aff6"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Get information about your cluster nodes and their status  (Query 14) (Cluster Node Properties)\r\n",
                "\r\n",
                "> Skip this query  if you know you don't have a clustered instance."
            ],
            "metadata": {
                "azdata_cell_guid": "ab43a838-f262-4af3-b74b-395aa6d31a87"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Get information about your cluster nodes and their status  (Query 14) (Cluster Node Properties)\r\n",
                "-- (if your database server is in a failover cluster)\r\n",
                "SELECT NodeName, status_description, is_current_owner\r\n",
                "FROM sys.dm_os_cluster_nodes WITH (NOLOCK) OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "78fa7839-330f-42e4-93b0-aa6972b50da6",
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
                "- Knowing which node owns the cluster resources is critical\r\n",
                "- Especially when you are installing Windows or SQL Server updates\r\n",
                "- You will see no results if your instance is not clustered"
            ],
            "metadata": {
                "azdata_cell_guid": "05eb7bd6-5226-4b4f-acf9-263f3c45db9b"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Get information about any AG cluster this instance is a part of (Query 15) (AG Cluster)\r\n",
                "> Skip this query  if you know you don't have a clustered instance."
            ],
            "metadata": {
                "azdata_cell_guid": "f2bf6ab3-2297-4ffc-aa8d-6e58451097bc"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Get information about any AG cluster this instance is a part of (Query 15) (AG Cluster)\r\n",
                "SELECT cluster_name, quorum_type_desc, quorum_state_desc\r\n",
                "FROM sys.dm_hadr_cluster WITH (NOLOCK) OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "be66842d-2596-455e-8133-935a334fa33f",
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
                "You will see no results if your instance is not using availability groups"
            ],
            "metadata": {
                "azdata_cell_guid": "a077d250-44dd-4d58-a714-eb271f306a4d"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Good overview of AG health and status (Query 16) (AG Status)\r\n",
                "> Skip this query  if you know you don't have a clustered instance."
            ],
            "metadata": {
                "azdata_cell_guid": "00b797ff-0560-45c4-a117-27a8710d775f"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Good overview of AG health and status (Query 16) (AG Status)\r\n",
                "SELECT ag.name AS [AG Name], ar.replica_server_name, ar.availability_mode_desc, adc.[database_name], \r\n",
                "       drs.is_local, drs.is_primary_replica, drs.synchronization_state_desc, drs.is_commit_participant, \r\n",
                "\t   drs.synchronization_health_desc, drs.recovery_lsn, drs.truncation_lsn, drs.last_sent_lsn, \r\n",
                "\t   drs.last_sent_time, drs.last_received_lsn, drs.last_received_time, drs.last_hardened_lsn, \r\n",
                "\t   drs.last_hardened_time, drs.last_redone_lsn, drs.last_redone_time, drs.log_send_queue_size, \r\n",
                "\t   drs.log_send_rate, drs.redo_queue_size, drs.redo_rate, drs.filestream_send_rate, \r\n",
                "\t   drs.end_of_log_lsn, drs.last_commit_lsn, drs.last_commit_time, drs.database_state_desc \r\n",
                "FROM sys.dm_hadr_database_replica_states AS drs WITH (NOLOCK)\r\n",
                "INNER JOIN sys.availability_databases_cluster AS adc WITH (NOLOCK)\r\n",
                "ON drs.group_id = adc.group_id \r\n",
                "AND drs.group_database_id = adc.group_database_id\r\n",
                "INNER JOIN sys.availability_groups AS ag WITH (NOLOCK)\r\n",
                "ON ag.group_id = drs.group_id\r\n",
                "INNER JOIN sys.availability_replicas AS ar WITH (NOLOCK)\r\n",
                "ON drs.group_id = ar.group_id \r\n",
                "AND drs.replica_id = ar.replica_id\r\n",
                "ORDER BY ag.name, ar.replica_server_name, adc.[database_name] OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "5a187fc2-a76f-48fa-91e6-60c255befda6",
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
                "You will see no results if your instance is not using availability groups"
            ],
            "metadata": {
                "azdata_cell_guid": "eabad768-614d-44ac-8a7e-b64d671ad5d9"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Hardware information from SQL Server 2019  (Query 17) (Hardware Info)"
            ],
            "metadata": {
                "azdata_cell_guid": "c56711f5-409f-4e52-ba2c-d9769daff5da"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Hardware information from SQL Server 2017  (Query 17) (Hardware Info)\r\n",
                "SELECT cpu_count AS [Logical CPU Count], scheduler_count, \r\n",
                "       (socket_count * cores_per_socket) AS [Physical Core Count], \r\n",
                "       socket_count AS [Socket Count], cores_per_socket, numa_node_count,\r\n",
                "       physical_memory_kb/1024 AS [Physical Memory (MB)], \r\n",
                "       max_workers_count AS [Max Workers Count], \r\n",
                "\t   affinity_type_desc AS [Affinity Type], \r\n",
                "       sqlserver_start_time AS [SQL Server Start Time],\r\n",
                "\t   DATEDIFF(hour, sqlserver_start_time, GETDATE()) AS [SQL Server Up Time (hrs)],\r\n",
                "\t   virtual_machine_type_desc AS [Virtual Machine Type], \r\n",
                "       softnuma_configuration_desc AS [Soft NUMA Configuration], \r\n",
                "\t   sql_memory_model_desc, process_physical_affinity -- New in SQL Server 2017\r\n",
                "FROM sys.dm_os_sys_info WITH (NOLOCK) OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "eb686beb-5353-4216-ac00-61a6ea082aa2",
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
                "Gives you some good basic hardware information about your database server\r\n",
                "\r\n",
                "**Note:** virtual_machine_type_desc of HYPERVISOR does not automatically mean you are running SQL Server inside of a VM.\r\n",
                "It merely indicates that you have a hypervisor running on your host\r\n",
                "\r\n",
                "[sys.dm_os_sys_info (Transact-SQL)](https://bit.ly/2pczOYs)\r\n",
                "\r\n",
                "Soft NUMA configuration was a new column for SQL Server 2016\r\n",
                "- OFF = Soft-NUMA feature is OFF\r\n",
                "- ON = SQL Server automatically determines the NUMA node sizes for Soft-NUMA\r\n",
                "- MANUAL = Manually configured soft-NUMA\r\n",
                "\r\n",
                "[Configure SQL Server to Use Soft-NUMA (SQL Server)](https://bit.ly/2HTpKJt)\r\n",
                "\r\n",
                "sql_memory_model_desc values (Added in SQL Server 2016 SP1)\r\n",
                "- CONVENTIONAL\r\n",
                "- LOCK_PAGES\r\n",
                "- LARGE_PAGES"
            ],
            "metadata": {
                "azdata_cell_guid": "84a101cc-0378-4a9e-83f3-5b6da75453b9"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Get System Manufacturer and model number from SQL Server Error log (Query 18) (System Manufacturer)"
            ],
            "metadata": {
                "azdata_cell_guid": "3eedfa3e-9fbe-4abd-a5a3-ba9b773cab2b"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Get System Manufacturer and model number from SQL Server Error log (Query 18) (System Manufacturer)\r\n",
                "EXEC sys.xp_readerrorlog 0, 1, N'Manufacturer';"
            ],
            "metadata": {
                "azdata_cell_guid": "aa9df5d5-9d4c-4ea4-a719-8edb5c1ac455",
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
                "This can help you determine the capabilities and capacities of your database server\r\n",
                "- Can also be used to confirm if you are running in a VM\r\n",
                "- This query might take a few seconds if you have not recycled your error log recently\r\n",
                "- This query will return no results if your error log has been recycled since the instance was started"
            ],
            "metadata": {
                "azdata_cell_guid": "ae092e1a-5d9f-4a51-994b-3fd570bd922d"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Get BIOS date from Windows Registry (Query 19) (BIOS Date)"
            ],
            "metadata": {
                "azdata_cell_guid": "cb9fd18a-e405-40e4-a2af-d9be8dffe36f"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Get BIOS date from Windows Registry (Query 19) (BIOS Date)\r\n",
                "EXEC sys.xp_instance_regread N'HKEY_LOCAL_MACHINE', N'HARDWARE\\DESCRIPTION\\System\\BIOS', N'BiosReleaseDate';"
            ],
            "metadata": {
                "azdata_cell_guid": "7345348c-6f3a-48f7-8072-b62b295c2289",
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
                "Helps you understand whether the main system BIOS is up to date, and the possible age of the hardware\r\n",
                "- Not as useful for virtualization\r\n",
                "- Does not work on Linux"
            ],
            "metadata": {
                "azdata_cell_guid": "07ed0dc3-b4ef-4341-b40b-a571d7be1dd5"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Get processor description from Windows Registry  (Query 20) (Processor Description)"
            ],
            "metadata": {
                "azdata_cell_guid": "d36e4da6-6371-4324-a021-582f7cd2dbba"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Get processor description from Windows Registry  (Query 20) (Processor Description)\r\n",
                "EXEC sys.xp_instance_regread N'HKEY_LOCAL_MACHINE', N'HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0', N'ProcessorNameString';"
            ],
            "metadata": {
                "azdata_cell_guid": "bd098885-6c92-4000-a275-71730bb7ab19",
                "tags": []
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "Gives you the model number and rated clock speed of your processor(s)\r\n",
                "- Your processors may be running at less than the rated clock speed due to the Windows Power Plan or hardware power management\r\n",
                "- Does not work on Linux\r\n",
                "\r\n",
                "You can use [CPU-Z](https://bit.ly/QhR6xF) to get your actual CPU core speed and a lot of other useful information\r\n",
                "\r\n",
                "You can learn more about processor selection for SQL Server by [following this link](https://bit.ly/2F3aVlP)\r\n",
                ""
            ],
            "metadata": {
                "azdata_cell_guid": "ee95e64f-008c-44d1-92d4-0da6e1aff02a"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Get information on location, time and size of any memory dumps from SQL Server  (Query 21) (Memory Dump Info)"
            ],
            "metadata": {
                "azdata_cell_guid": "53481628-9dc1-496c-b1a6-f0e3c28c9ffe"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Get information on location, time and size of any memory dumps from SQL Server  (Query 21) (Memory Dump Info)\r\n",
                "SELECT [filename], creation_time, size_in_bytes/1048576.0 AS [Size (MB)]\r\n",
                "FROM sys.dm_server_memory_dumps WITH (NOLOCK) \r\n",
                "ORDER BY creation_time DESC OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "fccec59e-6179-4581-9a60-301a8336c7ae",
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
                "This will not return any rows if you have not had any memory dumps (which is a good thing)\r\n",
                "\r\n",
                "[sys.dm_server_memory_dumps (Transact-SQL)](https://bit.ly/2elwWll)"
            ],
            "metadata": {
                "azdata_cell_guid": "189e6c64-2837-4188-b77f-2cfbb88add4d"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Look at Suspect Pages table (Query 22) (Suspect Pages)"
            ],
            "metadata": {
                "azdata_cell_guid": "db0d1c4c-2a1a-4fa9-bbeb-b87e8cd0fe17"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Look at Suspect Pages table (Query 22) (Suspect Pages)\r\n",
                "SELECT DB_NAME(database_id) AS [Database Name], [file_id], page_id, \r\n",
                "       event_type, error_count, last_update_date \r\n",
                "FROM msdb.dbo.suspect_pages WITH (NOLOCK)\r\n",
                "ORDER BY database_id OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "5d33ca2b-10c2-48af-8915-6f8f1e0aec8d",
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
                "**event_type value descriptions**\r\n",
                "- 1 = 823 error caused by an operating system CRC error or 824 error other than a bad checksum or a torn page (for example, a bad page ID)\r\n",
                "- 2 = Bad checksum\r\n",
                "- 3 = Torn page\r\n",
                "- 4 = Restored (The page was restored after it was marked bad)\r\n",
                "- 5 = Repaired (DBCC repaired the page)\r\n",
                "- 7 = Deallocated by DBCC\r\n",
                "\r\n",
                "Ideally, this query returns no results. The table is limited to 1000 rows.\r\n",
                "If you do get results here, you should do further investigation to determine the root cause\r\n",
                "\r\n",
                "[Manage the suspect_pages Table](https://bit.ly/2Fvr1c9)"
            ],
            "metadata": {
                "azdata_cell_guid": "45a39d5b-550d-48f7-976e-55c372111401"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Get number of data files in tempdb database (Query 23) (TempDB Data Files)"
            ],
            "metadata": {
                "azdata_cell_guid": "0d5055e2-2117-48c8-be77-1bbb4af676c1"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Get number of data files in tempdb database (Query 23) (TempDB Data Files)\r\n",
                "EXEC sys.xp_readerrorlog 0, 1, N'The tempdb database has';"
            ],
            "metadata": {
                "azdata_cell_guid": "cc56b4d2-3205-4e8b-91b4-89d123e1e486",
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
                "Returns the number of data files in the tempdb database\r\n",
                "- 4-8 data files that are all the same size is a good starting point\r\n",
                "- This query will return no results if your error log has been recycled since the instance was last started"
            ],
            "metadata": {
                "azdata_cell_guid": "632d349b-c763-4b59-9a34-e1004916c791"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## File names and paths for all user and system databases on instance  (Query 24) (Database Filenames and Paths)"
            ],
            "metadata": {
                "azdata_cell_guid": "eae14ae0-696c-4790-b6a3-a7c7e79a6201"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- File names and paths for all user and system databases on instance  (Query 24) (Database Filenames and Paths)\r\n",
                "SELECT DB_NAME([database_id]) AS [Database Name], \r\n",
                "       [file_id], [name], physical_name, [type_desc], state_desc,\r\n",
                "\t   is_percent_growth, growth, \r\n",
                "\t   CONVERT(bigint, growth/128.0) AS [Growth in MB], \r\n",
                "       CONVERT(bigint, size/128.0) AS [Total Size in MB], max_size\r\n",
                "FROM sys.master_files WITH (NOLOCK)\r\n",
                "ORDER BY DB_NAME([database_id]), [file_id] OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "171c61dc-022f-4f70-91c9-10c894eaf8ac",
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
                "- Are data files and log files on different drives?\r\n",
                "- Is everything on the C: drive?\r\n",
                "- Is tempdb on dedicated drives?\r\n",
                "- Is there only one tempdb data file?\r\n",
                "- Are all of the tempdb data files the same size?\r\n",
                "- Are there multiple data files for user databases?\r\n",
                "- Is percent growth enabled for any files (which is bad)?"
            ],
            "metadata": {
                "azdata_cell_guid": "e0e5564c-353d-4100-bdd0-1a2f71ee0ae8"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Drive information for all fixed drives visible to the operating system (Query 25) (Fixed Drives)"
            ],
            "metadata": {
                "azdata_cell_guid": "9ef7a9c7-c1b0-40d5-bbaf-4439616b9976"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Drive information for all fixed drives visible to the operating system (Query 25) (Fixed Drives)\r\n",
                "SELECT fixed_drive_path, drive_type_desc, \r\n",
                "CONVERT(DECIMAL(18,2), free_space_in_bytes/1073741824.0) AS [Available Space (GB)]\r\n",
                "FROM sys.dm_os_enumerate_fixed_drives WITH (NOLOCK) OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "bc1e9f79-18d8-432d-a73b-d286d2c08a96",
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
                "This shows all of your fixed drives, not just LUNs with SQL Server database files"
            ],
            "metadata": {
                "azdata_cell_guid": "57ada56f-76df-40e1-9163-7cc410edc565"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Volume info for all LUNS that have database files on the current instance (Query 26) (Volume Info)"
            ],
            "metadata": {
                "azdata_cell_guid": "20a2d365-d06d-4f80-8b2e-55d5f7466068"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Volume info for all LUNS that have database files on the current instance (Query 26) (Volume Info)\r\n",
                "SELECT DISTINCT vs.volume_mount_point, vs.file_system_type, vs.logical_volume_name, \r\n",
                "CONVERT(DECIMAL(18,2), vs.total_bytes/1073741824.0) AS [Total Size (GB)],\r\n",
                "CONVERT(DECIMAL(18,2), vs.available_bytes/1073741824.0) AS [Available Size (GB)],  \r\n",
                "CONVERT(DECIMAL(18,2), vs.available_bytes * 1. / vs.total_bytes * 100.) AS [Space Free %],\r\n",
                "vs.supports_compression, vs.is_compressed, \r\n",
                "vs.supports_sparse_files, vs.supports_alternate_streams\r\n",
                "FROM sys.master_files AS f WITH (NOLOCK)\r\n",
                "CROSS APPLY sys.dm_os_volume_stats(f.database_id, f.[file_id]) AS vs \r\n",
                "ORDER BY vs.volume_mount_point OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "0edfcf07-632d-4f97-a2ff-5cec35d7b55b",
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
                "## Drive level latency information (Query 27) (Drive Level Latency)"
            ],
            "metadata": {
                "azdata_cell_guid": "43f20e94-8a19-487b-b17f-906f77e1d353"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Drive level latency information (Query 27) (Drive Level Latency)\r\n",
                "SELECT tab.[Drive], tab.volume_mount_point AS [Volume Mount Point], \r\n",
                "\tCASE \r\n",
                "\t\tWHEN num_of_reads = 0 THEN 0 \r\n",
                "\t\tELSE (io_stall_read_ms/num_of_reads) \r\n",
                "\tEND AS [Read Latency],\r\n",
                "\tCASE \r\n",
                "\t\tWHEN num_of_writes = 0 THEN 0 \r\n",
                "\t\tELSE (io_stall_write_ms/num_of_writes) \r\n",
                "\tEND AS [Write Latency],\r\n",
                "\tCASE \r\n",
                "\t\tWHEN (num_of_reads = 0 AND num_of_writes = 0) THEN 0 \r\n",
                "\t\tELSE (io_stall/(num_of_reads + num_of_writes)) \r\n",
                "\tEND AS [Overall Latency],\r\n",
                "\tCASE \r\n",
                "\t\tWHEN num_of_reads = 0 THEN 0 \r\n",
                "\t\tELSE (num_of_bytes_read/num_of_reads) \r\n",
                "\tEND AS [Avg Bytes/Read],\r\n",
                "\tCASE \r\n",
                "\t\tWHEN num_of_writes = 0 THEN 0 \r\n",
                "\t\tELSE (num_of_bytes_written/num_of_writes) \r\n",
                "\tEND AS [Avg Bytes/Write],\r\n",
                "\tCASE \r\n",
                "\t\tWHEN (num_of_reads = 0 AND num_of_writes = 0) THEN 0 \r\n",
                "\t\tELSE ((num_of_bytes_read + num_of_bytes_written)/(num_of_reads + num_of_writes)) \r\n",
                "\tEND AS [Avg Bytes/Transfer]\r\n",
                "FROM (SELECT LEFT(UPPER(mf.physical_name), 2) AS Drive, SUM(num_of_reads) AS num_of_reads,\r\n",
                "\t         SUM(io_stall_read_ms) AS io_stall_read_ms, SUM(num_of_writes) AS num_of_writes,\r\n",
                "\t         SUM(io_stall_write_ms) AS io_stall_write_ms, SUM(num_of_bytes_read) AS num_of_bytes_read,\r\n",
                "\t         SUM(num_of_bytes_written) AS num_of_bytes_written, SUM(io_stall) AS io_stall, vs.volume_mount_point \r\n",
                "      FROM sys.dm_io_virtual_file_stats(NULL, NULL) AS vfs\r\n",
                "      INNER JOIN sys.master_files AS mf WITH (NOLOCK)\r\n",
                "      ON vfs.database_id = mf.database_id AND vfs.file_id = mf.file_id\r\n",
                "\t  CROSS APPLY sys.dm_os_volume_stats(mf.database_id, mf.[file_id]) AS vs \r\n",
                "      GROUP BY LEFT(UPPER(mf.physical_name), 2), vs.volume_mount_point) AS tab\r\n",
                "ORDER BY [Overall Latency] OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "ed4f034e-e588-4296-a204-9c904050b2ba",
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
                "Shows you the drive-level latency for reads and writes, in milliseconds\r\n",
                "- Latency above 30-40ms is usually a problem\r\n",
                "- These latency numbers include all file activity against all SQL Server database files on each drive since SQL Server was last started"
            ],
            "metadata": {
                "azdata_cell_guid": "0d87cae3-f880-4d58-a950-64d98a9f4b55"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Calculates average latency per read, per write, and per total input/output for each database file  (Query 28) (IO Latency by File)"
            ],
            "metadata": {
                "azdata_cell_guid": "e8034da3-9f7e-43df-82bc-27e103a3978c"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Calculates average latency per read, per write, and per total input/output for each database file  (Query 28) (IO Latency by File)\r\n",
                "SELECT DB_NAME(fs.database_id) AS [Database Name], CAST(fs.io_stall_read_ms/(1.0 + fs.num_of_reads) AS NUMERIC(10,1)) AS [avg_read_latency_ms],\r\n",
                "CAST(fs.io_stall_write_ms/(1.0 + fs.num_of_writes) AS NUMERIC(10,1)) AS [avg_write_latency_ms],\r\n",
                "CAST((fs.io_stall_read_ms + fs.io_stall_write_ms)/(1.0 + fs.num_of_reads + fs.num_of_writes) AS NUMERIC(10,1)) AS [avg_io_latency_ms],\r\n",
                "CONVERT(DECIMAL(18,2), mf.size/128.0) AS [File Size (MB)], mf.physical_name, mf.type_desc, fs.io_stall_read_ms, fs.num_of_reads, \r\n",
                "fs.io_stall_write_ms, fs.num_of_writes, fs.io_stall_read_ms + fs.io_stall_write_ms AS [io_stalls], fs.num_of_reads + fs.num_of_writes AS [total_io],\r\n",
                "io_stall_queued_read_ms AS [Resource Governor Total Read IO Latency (ms)], io_stall_queued_write_ms AS [Resource Governor Total Write IO Latency (ms)] \r\n",
                "FROM sys.dm_io_virtual_file_stats(null,null) AS fs\r\n",
                "INNER JOIN sys.master_files AS mf WITH (NOLOCK)\r\n",
                "ON fs.database_id = mf.database_id\r\n",
                "AND fs.[file_id] = mf.[file_id]\r\n",
                "ORDER BY avg_io_latency_ms DESC OPTION (RECOMPILE);"
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
                "## Look for I/O requests taking longer than 15 seconds in the six most recent SQL Server Error Logs (Query 29) (IO Warnings)"
            ],
            "metadata": {
                "azdata_cell_guid": "9c8a87dc-3649-4813-acbf-563c4b42ba87"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Look for I/O requests taking longer than 15 seconds in the six most recent SQL Server Error Logs (Query 29) (IO Warnings)\r\n",
                "CREATE TABLE #IOWarningResults(LogDate datetime, ProcessInfo sysname, LogText nvarchar(1000));\r\n",
                "\r\n",
                "\tINSERT INTO #IOWarningResults \r\n",
                "\tEXEC xp_readerrorlog 0, 1, N'taking longer than 15 seconds';\r\n",
                "\r\n",
                "\tINSERT INTO #IOWarningResults \r\n",
                "\tEXEC xp_readerrorlog 1, 1, N'taking longer than 15 seconds';\r\n",
                "\r\n",
                "\tINSERT INTO #IOWarningResults \r\n",
                "\tEXEC xp_readerrorlog 2, 1, N'taking longer than 15 seconds';\r\n",
                "\r\n",
                "\tINSERT INTO #IOWarningResults \r\n",
                "\tEXEC xp_readerrorlog 3, 1, N'taking longer than 15 seconds';\r\n",
                "\r\n",
                "\tINSERT INTO #IOWarningResults \r\n",
                "\tEXEC xp_readerrorlog 4, 1, N'taking longer than 15 seconds';\r\n",
                "\r\n",
                "\tINSERT INTO #IOWarningResults \r\n",
                "\tEXEC xp_readerrorlog 5, 1, N'taking longer than 15 seconds';\r\n",
                "\r\n",
                "SELECT LogDate, ProcessInfo, LogText\r\n",
                "FROM #IOWarningResults\r\n",
                "ORDER BY LogDate DESC;\r\n",
                "\r\n",
                "DROP TABLE #IOWarningResults;"
            ],
            "metadata": {
                "azdata_cell_guid": "152d907d-1cd7-4cc3-8f44-530064c21072",
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
                "Finding 15 second I/O warnings in the SQL Server Error Log is useful evidence of\r\n",
                "poor I/O performance (which might have many different causes)\r\n",
                "Look to see if you see any patterns in the results (same files, same drives, same time of day, etc.)\r\n",
                "\r\n",
                "[Diagnostics in SQL Server help detect stalled and stuck I/O operations](https://bit.ly/2qtaw73)\r\n",
                ""
            ],
            "metadata": {
                "azdata_cell_guid": "74e661b2-b162-4951-9cec-d8a6484944d5"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Resource Governor Resource Pool information (Query 30) (RG Resource Pools)"
            ],
            "metadata": {
                "azdata_cell_guid": "288fd42f-85f0-4245-a264-b42b7bd71251"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Resource Governor Resource Pool information (Query 30) (RG Resource Pools)\r\n",
                "SELECT pool_id, [Name], statistics_start_time,\r\n",
                "       min_memory_percent, max_memory_percent,  \r\n",
                "       max_memory_kb/1024 AS [max_memory_mb],  \r\n",
                "       used_memory_kb/1024 AS [used_memory_mb],   \r\n",
                "       target_memory_kb/1024 AS [target_memory_mb],\r\n",
                "\t   min_iops_per_volume, max_iops_per_volume\r\n",
                "FROM sys.dm_resource_governor_resource_pools WITH (NOLOCK)\r\n",
                "OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "3c5a64ef-ed1a-4bdc-a2c2-dac704fce7db",
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
                "[sys.dm_resource_governor_resource_pools (Transact-SQL)](https://bit.ly/2MVU0Vy)"
            ],
            "metadata": {
                "azdata_cell_guid": "8a1d064d-17ce-4d60-9ec1-9ad760f6e7ba"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Recovery model, log reuse wait description, log file size, log usage size  (Query 31) (Database Properties)"
            ],
            "metadata": {
                "azdata_cell_guid": "011889f4-ab02-4cc4-b95e-f0bfce336b07"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Recovery model, log reuse wait description, log file size, log usage size  (Query 31) (Database Properties)\r\n",
                "-- and compatibility level for all databases on instance\r\n",
                "SELECT db.[name] AS [Database Name], SUSER_SNAME(db.owner_sid) AS [Database Owner], db.recovery_model_desc AS [Recovery Model], \r\n",
                "db.state_desc, db.containment_desc, db.log_reuse_wait_desc AS [Log Reuse Wait Description], \r\n",
                "CONVERT(DECIMAL(18,2), ls.cntr_value/1024.0) AS [Log Size (MB)], CONVERT(DECIMAL(18,2), lu.cntr_value/1024.0) AS [Log Used (MB)],\r\n",
                "CAST(CAST(lu.cntr_value AS FLOAT) / CAST(ls.cntr_value AS FLOAT)AS DECIMAL(18,2)) * 100 AS [Log Used %], \r\n",
                "db.[compatibility_level] AS [DB Compatibility Level], \r\n",
                "db.is_mixed_page_allocation_on, db.page_verify_option_desc AS [Page Verify Option], \r\n",
                "db.is_auto_create_stats_on, db.is_auto_update_stats_on, db.is_auto_update_stats_async_on, db.is_parameterization_forced, \r\n",
                "db.snapshot_isolation_state_desc, db.is_read_committed_snapshot_on, db.is_auto_close_on, db.is_auto_shrink_on, \r\n",
                "db.target_recovery_time_in_seconds, db.is_cdc_enabled, db.is_published, db.is_distributor,\r\n",
                "db.group_database_id, db.replica_id,db.is_memory_optimized_elevate_to_snapshot_on, \r\n",
                "db.delayed_durability_desc, db.is_auto_create_stats_incremental_on,\r\n",
                "db.is_query_store_on, db.is_sync_with_backup, db.is_temporal_history_retention_enabled,\r\n",
                "db.is_supplemental_logging_enabled, db.is_remote_data_archive_enabled,\r\n",
                "db.is_encrypted, de.encryption_state, de.percent_complete, de.key_algorithm, de.key_length, db.resource_pool_id      \r\n",
                "FROM sys.databases AS db WITH (NOLOCK)\r\n",
                "INNER JOIN sys.dm_os_performance_counters AS lu WITH (NOLOCK)\r\n",
                "ON db.name = lu.instance_name\r\n",
                "INNER JOIN sys.dm_os_performance_counters AS ls WITH (NOLOCK)\r\n",
                "ON db.name = ls.instance_name\r\n",
                "LEFT OUTER JOIN sys.dm_database_encryption_keys AS de WITH (NOLOCK)\r\n",
                "ON db.database_id = de.database_id\r\n",
                "WHERE lu.counter_name LIKE N'Log File(s) Used Size (KB)%' \r\n",
                "AND ls.counter_name LIKE N'Log File(s) Size (KB)%'\r\n",
                "AND ls.cntr_value > 0 \r\n",
                "ORDER BY db.[name] OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "10178c97-5516-44e0-85d5-2c2a2351b390",
                "tags": []
            },
            "outputs": [],
            "execution_count": null
        },
        {
            "cell_type": "markdown",
            "source": [
                "Things to look at:\r\n",
                "- How many databases are on the instance?\r\n",
                "- What recovery models are they using?\r\n",
                "- What is the log reuse wait description?\r\n",
                "- How full are the transaction logs?\r\n",
                "- What compatibility level are the databases on? \r\n",
                "- What is the Page Verify Option? (should be CHECKSUM)\r\n",
                "- Is Auto Update Statistics Asynchronously enabled?\r\n",
                "- What is target_recovery_time_in_seconds?\r\n",
                "- Is Delayed Durability enabled?\r\n",
                "- Make sure auto_shrink and auto_close are not enabled!\r\n",
                "\r\n",
                "is_mixed_page_allocation_on is a new property for SQL Server 2016. Equivalent to TF 1118 for a user database\r\n",
                "\r\n",
                "[SQL Server 2016: Changes in default behavior for autogrow and allocations for tempdb and user databases](https://bit.ly/2evRZSR)\r\n",
                "\r\n",
                "A non-zero value for target_recovery_time_in_seconds means that indirect checkpoint is enabled \r\n",
                "If the setting has a zero value it indicates that automatic checkpoint is enabled\r\n",
                "\r\n",
                "[Changes in SQL Server 2016 Checkpoint Behavior](https://bit.ly/2pdggk3)"
            ],
            "metadata": {
                "azdata_cell_guid": "87c25aa8-958a-40e2-aacb-3b7ebafbb282"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Missing Indexes for all databases by Index Advantage  (Query 32) (Missing Indexes All Databases)"
            ],
            "metadata": {
                "azdata_cell_guid": "630e96b9-c67c-43d4-935b-e0dd561dc8ac"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Missing Indexes for all databases by Index Advantage  (Query 32) (Missing Indexes All Databases)\r\n",
                "SELECT CONVERT(decimal(18,2), migs.user_seeks * migs.avg_total_user_cost * (migs.avg_user_impact * 0.01)) AS [index_advantage],\r\n",
                "FORMAT(migs.last_user_seek, 'yyyy-MM-dd HH:mm:ss') AS [last_user_seek], mid.[statement] AS [Database.Schema.Table],\r\n",
                "COUNT(1) OVER(PARTITION BY mid.[statement]) AS [missing_indexes_for_table],\r\n",
                "COUNT(1) OVER(PARTITION BY mid.[statement], mid.equality_columns) AS [similar_missing_indexes_for_table],\r\n",
                "mid.equality_columns, mid.inequality_columns, mid.included_columns, migs.user_seeks, \r\n",
                "CONVERT(decimal(18,2), migs.avg_total_user_cost) AS [avg_total_user_cost], migs.avg_user_impact \r\n",
                "FROM sys.dm_db_missing_index_group_stats AS migs WITH (NOLOCK)\r\n",
                "INNER JOIN sys.dm_db_missing_index_groups AS mig WITH (NOLOCK)\r\n",
                "ON migs.group_handle = mig.index_group_handle\r\n",
                "INNER JOIN sys.dm_db_missing_index_details AS mid WITH (NOLOCK)\r\n",
                "ON mig.index_handle = mid.index_handle\r\n",
                "ORDER BY index_advantage DESC OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "f6ee176a-6fc6-4533-8878-47bda0e3cdd8",
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
                "Getting missing index information for all of the databases on the instance is very useful\r\n",
                "- Look at last user seek time, number of user seeks to help determine source and importance\r\n",
                "- Also look at avg_user_impact and avg_total_user_cost to help determine importance\r\n",
                "- SQL Server is overly eager to add included columns, so beware\r\n",
                "- Do not just blindly add indexes that show up from this query!!!\r\n",
                "\r\n",
                "Håkan Winther has given me some great suggestions for this query\r\n",
                "\r\n",
                "[SQL Server Index Design Guide](https://bit.ly/2qtZr4N)"
            ],
            "metadata": {
                "azdata_cell_guid": "0031037b-0eeb-431e-986e-5a4d73594583"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Get VLF Counts for all databases on the instance (Query 33) (VLF Counts)"
            ],
            "metadata": {
                "azdata_cell_guid": "74e5c58c-81fc-4adb-a1a2-e589b957a957"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Get VLF Counts for all databases on the instance (Query 33) (VLF Counts)\r\n",
                "SELECT [name] AS [Database Name], [VLF Count]\r\n",
                "FROM sys.databases AS db WITH (NOLOCK)\r\n",
                "CROSS APPLY (SELECT file_id, COUNT(*) AS [VLF Count]\r\n",
                "\t\t     FROM sys.dm_db_log_info(db.database_id)\r\n",
                "\t\t\t GROUP BY file_id) AS li\r\n",
                "ORDER BY [VLF Count] DESC OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "0743a5b0-c306-426a-8be1-906b8caf1524",
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
                "High VLF counts can affect write performance to the log file,\r\n",
                "and they can make full database restores and crash recovery take much longer.\r\n",
                "Try to keep your VLF counts under 200 in most cases (depending on log file size)\r\n",
                "\r\n",
                "[Important change to VLF creation algorithm in SQL Server 2014](https://bit.ly/2Hsjbg4)\r\n",
                "\r\n",
                "[SQL Server Transaction Log Architecture and Management Guide](https://bit.ly/2JjmQRZ)\r\n",
                ""
            ],
            "metadata": {
                "azdata_cell_guid": "b4515bae-6989-437a-a8af-3441a3951fdd"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Get CPU utilization by database (Query 34) (CPU Usage by Database)"
            ],
            "metadata": {
                "azdata_cell_guid": "9571542a-c0f2-4940-925c-3f093bef68fd"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Get CPU utilization by database (Query 34) (CPU Usage by Database)\r\n",
                "WITH DB_CPU_Stats\r\n",
                "AS\r\n",
                "(SELECT pa.DatabaseID, DB_Name(pa.DatabaseID) AS [Database Name], SUM(qs.total_worker_time/1000) AS [CPU_Time_Ms]\r\n",
                " FROM sys.dm_exec_query_stats AS qs WITH (NOLOCK)\r\n",
                " CROSS APPLY (SELECT CONVERT(int, value) AS [DatabaseID] \r\n",
                "              FROM sys.dm_exec_plan_attributes(qs.plan_handle)\r\n",
                "              WHERE attribute = N'dbid') AS pa\r\n",
                " GROUP BY DatabaseID)\r\n",
                "SELECT ROW_NUMBER() OVER(ORDER BY [CPU_Time_Ms] DESC) AS [CPU Rank],\r\n",
                "       [Database Name], [CPU_Time_Ms] AS [CPU Time (ms)], \r\n",
                "       CAST([CPU_Time_Ms] * 1.0 / SUM([CPU_Time_Ms]) OVER() * 100.0 AS DECIMAL(5, 2)) AS [CPU Percent]\r\n",
                "FROM DB_CPU_Stats\r\n",
                "WHERE DatabaseID <> 32767 -- ResourceDB\r\n",
                "ORDER BY [CPU Rank] OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "3129e437-2004-4728-83c9-220372eeecc3",
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
                "Helps determine which database is using the most CPU resources on the instance \\\r\n",
                "**Note:** This only reflects CPU usage from the currently cached query plans"
            ],
            "metadata": {
                "azdata_cell_guid": "7236bd8c-e28c-49f1-9b85-6b9d26711587"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Get I/O utilization by database (Query 35) (IO Usage By Database)"
            ],
            "metadata": {
                "azdata_cell_guid": "4a21658f-4a40-413d-b5df-ba343bfdb094"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Get I/O utilization by database (Query 35) (IO Usage By Database)\r\n",
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
                "## Get total buffer usage by database for current instance  (Query 36) (Total Buffer Usage by Database)"
            ],
            "metadata": {
                "azdata_cell_guid": "e525a356-0a95-470b-bdd8-3200554d78ca"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Get total buffer usage by database for current instance  (Query 36) (Total Buffer Usage by Database)\r\n",
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
                "## Get tempdb version store space usage by database (Query 37) (Version Store Space Usage)"
            ],
            "metadata": {
                "azdata_cell_guid": "2773fbac-0d19-4e6a-9986-2bf98154b90a"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Get tempdb version store space usage by database (Query 37) (Version Store Space Usage)\r\n",
                "SELECT DB_NAME(database_id) AS [Database Name],\r\n",
                "       reserved_page_count AS [Version Store Reserved Page Count], \r\n",
                "\t   reserved_space_kb/1024 AS [Version Store Reserved Space (MB)] \r\n",
                "FROM sys.dm_tran_version_store_space_usage WITH (NOLOCK) \r\n",
                "ORDER BY reserved_space_kb/1024 DESC OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "65337a60-4ea7-4e0e-a16a-2597c122f18b",
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
                "[sys.dm_tran_version_store_space_usage (Transact-SQL)](https://bit.ly/2vh3Bmk)"
            ],
            "metadata": {
                "azdata_cell_guid": "54f7a43e-cfe5-4c50-b97d-53b312127bec"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Isolate top waits for server instance since last restart or wait statistics clear  (Query 38) (Top Waits)"
            ],
            "metadata": {
                "azdata_cell_guid": "f2e7ad2d-e602-45e6-8f6c-209ef090da40"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Clear Wait Stats with this command\r\n",
                "-- DBCC SQLPERF('sys.dm_os_wait_stats', CLEAR);\r\n",
                "\r\n",
                "-- Isolate top waits for server instance since last restart or wait statistics clear  (Query 38) (Top Waits)\r\n",
                "WITH [Waits] \r\n",
                "AS (SELECT wait_type, wait_time_ms/ 1000.0 AS [WaitS],\r\n",
                "          (wait_time_ms - signal_wait_time_ms) / 1000.0 AS [ResourceS],\r\n",
                "           signal_wait_time_ms / 1000.0 AS [SignalS],\r\n",
                "           waiting_tasks_count AS [WaitCount],\r\n",
                "           100.0 *  wait_time_ms / SUM (wait_time_ms) OVER() AS [Percentage],\r\n",
                "           ROW_NUMBER() OVER(ORDER BY wait_time_ms DESC) AS [RowNum]\r\n",
                "    FROM sys.dm_os_wait_stats WITH (NOLOCK)\r\n",
                "    WHERE [wait_type] NOT IN (\r\n",
                "        N'BROKER_EVENTHANDLER', N'BROKER_RECEIVE_WAITFOR', N'BROKER_TASK_STOP',\r\n",
                "\t\tN'BROKER_TO_FLUSH', N'BROKER_TRANSMITTER', N'CHECKPOINT_QUEUE',\r\n",
                "        N'CHKPT', N'CLR_AUTO_EVENT', N'CLR_MANUAL_EVENT', N'CLR_SEMAPHORE', N'CXCONSUMER',\r\n",
                "        N'DBMIRROR_DBM_EVENT', N'DBMIRROR_EVENTS_QUEUE', N'DBMIRROR_WORKER_QUEUE',\r\n",
                "\t\tN'DBMIRRORING_CMD', N'DIRTY_PAGE_POLL', N'DISPATCHER_QUEUE_SEMAPHORE',\r\n",
                "        N'EXECSYNC', N'FSAGENT', N'FT_IFTS_SCHEDULER_IDLE_WAIT', N'FT_IFTSHC_MUTEX',\r\n",
                "        N'HADR_CLUSAPI_CALL', N'HADR_FILESTREAM_IOMGR_IOCOMPLETION', N'HADR_LOGCAPTURE_WAIT', \r\n",
                "\t\tN'HADR_NOTIFICATION_DEQUEUE', N'HADR_TIMER_TASK', N'HADR_WORK_QUEUE',\r\n",
                "        N'KSOURCE_WAKEUP', N'LAZYWRITER_SLEEP', N'LOGMGR_QUEUE', \r\n",
                "\t\tN'MEMORY_ALLOCATION_EXT', N'ONDEMAND_TASK_QUEUE',\r\n",
                "\t\tN'PARALLEL_REDO_DRAIN_WORKER', N'PARALLEL_REDO_LOG_CACHE', N'PARALLEL_REDO_TRAN_LIST',\r\n",
                "\t\tN'PARALLEL_REDO_WORKER_SYNC', N'PARALLEL_REDO_WORKER_WAIT_WORK',\r\n",
                "\t\tN'PREEMPTIVE_HADR_LEASE_MECHANISM', N'PREEMPTIVE_SP_SERVER_DIAGNOSTICS',\r\n",
                "\t\tN'PREEMPTIVE_OS_LIBRARYOPS', N'PREEMPTIVE_OS_COMOPS', N'PREEMPTIVE_OS_CRYPTOPS',\r\n",
                "\t\tN'PREEMPTIVE_OS_PIPEOPS', N'PREEMPTIVE_OS_AUTHENTICATIONOPS',\r\n",
                "\t\tN'PREEMPTIVE_OS_GENERICOPS', N'PREEMPTIVE_OS_VERIFYTRUST',\r\n",
                "\t\tN'PREEMPTIVE_OS_FILEOPS', N'PREEMPTIVE_OS_DEVICEOPS', N'PREEMPTIVE_OS_QUERYREGISTRY',\r\n",
                "\t\tN'PREEMPTIVE_OS_WRITEFILE',\r\n",
                "\t\tN'PREEMPTIVE_XE_CALLBACKEXECUTE', N'PREEMPTIVE_XE_DISPATCHER',\r\n",
                "\t\tN'PREEMPTIVE_XE_GETTARGETSTATE', N'PREEMPTIVE_XE_SESSIONCOMMIT',\r\n",
                "\t\tN'PREEMPTIVE_XE_TARGETINIT', N'PREEMPTIVE_XE_TARGETFINALIZE',\r\n",
                "        N'PWAIT_ALL_COMPONENTS_INITIALIZED', N'PWAIT_DIRECTLOGCONSUMER_GETNEXT',\r\n",
                "\t\tN'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP',\r\n",
                "\t\tN'QDS_ASYNC_QUEUE',\r\n",
                "        N'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP', N'REQUEST_FOR_DEADLOCK_SEARCH',\r\n",
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
                "    CAST ((MAX (W1.SignalS) / MAX (W1.WaitCount)) AS DECIMAL (16,4)) AS [AvgSig_Sec], \r\n",
                "    CAST (MAX (W1.WaitS) AS DECIMAL (16,2)) AS [Wait_Sec],\r\n",
                "    CAST (MAX (W1.ResourceS) AS DECIMAL (16,2)) AS [Resource_Sec],\r\n",
                "    CAST (MAX (W1.SignalS) AS DECIMAL (16,2)) AS [Signal_Sec],\r\n",
                "    MAX (W1.WaitCount) AS [Wait Count],\r\n",
                "\tCAST (N'https://www.sqlskills.com/help/waits/' + W1.wait_type AS XML) AS [Help/Info URL]\r\n",
                "FROM Waits AS W1\r\n",
                "INNER JOIN Waits AS W2\r\n",
                "ON W2.RowNum <= W1.RowNum\r\n",
                "GROUP BY W1.RowNum, W1.wait_type\r\n",
                "HAVING SUM (W2.Percentage) - MAX (W1.Percentage) < 99 -- percentage threshold\r\n",
                "OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "255074eb-647d-4852-b476-c63ceb56cc9d",
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
                "azdata_cell_guid": "faf38e09-4c18-4c92-8e7c-01ea38fd08b6"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Get a count of SQL connections by IP address (Query 39) (Connection Counts by IP Address)"
            ],
            "metadata": {
                "azdata_cell_guid": "0299b6cd-25bd-4e92-be3d-1b0a26828a90"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Get a count of SQL connections by IP address (Query 39) (Connection Counts by IP Address)\r\n",
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
                "## Get Average Task Counts (run multiple times)  (Query 40) (Avg Task Counts)"
            ],
            "metadata": {
                "azdata_cell_guid": "ed4204b4-820a-4266-adc0-ae5fb48360a8"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Get Average Task Counts (run multiple times)  (Query 40) (Avg Task Counts)\r\n",
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
                "Sustained values above 10 suggest further investigation in that area\r\n",
                "- High Avg Task Counts are often caused by blocking/deadlocking or other resource contention\r\n",
                "\r\n",
                "Sustained values above 1 suggest further investigation in that area\r\n",
                "- High Avg Runnable Task Counts are a good sign of CPU pressure\r\n",
                "- High Avg Pending DiskIO Counts are a sign of disk pressure\r\n",
                "\r\n",
                "[How to Do Some Very Basic SQL Server Monitoring](https://bit.ly/30IRla0)\r\n",
                ""
            ],
            "metadata": {
                "azdata_cell_guid": "4500bb2c-6025-45fe-ad05-a54cc9a86a68"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Detect blocking (run multiple times)  (Query 41) (Detect Blocking)"
            ],
            "metadata": {
                "azdata_cell_guid": "76df2148-9a87-4642-9dfa-aae374ca8be1"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Detect blocking (run multiple times)  (Query 41) (Detect Blocking)\r\n",
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
                "## Get CPU Utilization History for last 256 minutes (in one minute intervals)  (Query 42) (CPU Utilization History)"
            ],
            "metadata": {
                "azdata_cell_guid": "e99406d7-9d91-4cc8-8486-21421e4fcca5"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Get CPU Utilization History for last 256 minutes (in one minute intervals)  (Query 42) (CPU Utilization History)\r\n",
                "DECLARE @ts_now bigint = (SELECT ms_ticks FROM sys.dm_os_sys_info WITH (NOLOCK)); \r\n",
                "\r\n",
                "SELECT TOP(256) SQLProcessUtilization AS [SQL Server Process CPU Utilization], \r\n",
                "               SystemIdle AS [System Idle Process], \r\n",
                "               100 - SystemIdle - SQLProcessUtilization AS [Other Process CPU Utilization], \r\n",
                "               DATEADD(ms, -1 * (@ts_now - [timestamp]), GETDATE()) AS [Event Time] \r\n",
                "FROM (SELECT record.value('(./Record/@id)[1]', 'int') AS record_id, \r\n",
                "              record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int') \r\n",
                "                      AS [SystemIdle], \r\n",
                "              record.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int') \r\n",
                "                      AS [SQLProcessUtilization], [timestamp] \r\n",
                "         FROM (SELECT [timestamp], CONVERT(xml, record) AS [record] \r\n",
                "                      FROM sys.dm_os_ring_buffers WITH (NOLOCK)\r\n",
                "                      WHERE ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR' \r\n",
                "                      AND record LIKE N'%<SystemHealth>%') AS x) AS y \r\n",
                "ORDER BY record_id DESC OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "b7187c90-75cd-4f2e-afaa-c5419f0f5c7d",
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
                "Look at the trend over the entire period \r\n",
                "- Also look at high sustained 'Other Process' CPU Utilization values\r\n",
                "- Note: This query sometimes gives inaccurate results (negative values) on high core count (> 64 cores) systems"
            ],
            "metadata": {
                "azdata_cell_guid": "2b34bfb5-1daa-461c-9c6d-5c2cab0f3b70"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Get top total worker time queries for entire instance (Query 43) (Top Worker Time Queries)"
            ],
            "metadata": {
                "azdata_cell_guid": "1d29e3a6-eaa1-40b2-a10f-4f9ea9b3135c"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Get top total worker time queries for entire instance (Query 43) (Top Worker Time Queries)\r\n",
                "SELECT TOP(50) DB_NAME(t.[dbid]) AS [Database Name], \r\n",
                "REPLACE(REPLACE(LEFT(t.[text], 255), CHAR(10),''), CHAR(13),'') AS [Short Query Text],  \r\n",
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
                "CASE WHEN CONVERT(nvarchar(max), qp.query_plan) COLLATE Latin1_General_BIN2 LIKE N'%<MissingIndexes>%' THEN 1 ELSE 0 END AS [Has Missing Index],\r\n",
                "qs.creation_time AS [Creation Time]\r\n",
                "--,t.[text] AS [Query Text], qp.query_plan AS [Query Plan] -- uncomment out these columns if not copying results to Excel\r\n",
                "FROM sys.dm_exec_query_stats AS qs WITH (NOLOCK)\r\n",
                "CROSS APPLY sys.dm_exec_sql_text(plan_handle) AS t \r\n",
                "CROSS APPLY sys.dm_exec_query_plan(plan_handle) AS qp \r\n",
                "ORDER BY qs.total_worker_time DESC OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "b1710c68-1a92-43a8-92b3-bcb347c9f18e",
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
                "Helps you find the most expensive queries from a CPU perspective across the entire instance\r\n",
                "- Can also help track down parameter sniffing issues"
            ],
            "metadata": {
                "azdata_cell_guid": "f64892d4-ed7d-4882-810f-4410b713b5bc"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Page Life Expectancy (PLE) value for each NUMA node in current instance  (Query 44) (PLE by NUMA Node)"
            ],
            "metadata": {
                "azdata_cell_guid": "20f52f6d-f822-4866-9148-d9b30fc07911"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Page Life Expectancy (PLE) value for each NUMA node in current instance  (Query 44) (PLE by NUMA Node)\r\n",
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
                "## Memory Grants Pending value for current instance  (Query 45) (Memory Grants Pending)"
            ],
            "metadata": {
                "azdata_cell_guid": "44308f96-e53e-4ead-94cb-281f705da51e"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Memory Grants Pending value for current instance  (Query 45) (Memory Grants Pending)\r\n",
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
                "## Memory Clerk Usage for instance  (Query 46) (Memory Clerk Usage)"
            ],
            "metadata": {
                "azdata_cell_guid": "c4c3cac5-c806-414d-a1bf-7e759ea761b1"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Memory Clerk Usage for instance  (Query 46) (Memory Clerk Usage)\r\n",
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
                "## Find single-use, ad-hoc and prepared queries that are bloating the plan cache  (Query 47) (Ad hoc Queries)"
            ],
            "metadata": {
                "azdata_cell_guid": "8c166c58-ca7f-4fa5-9f6f-d4570ddf2020"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Find single-use, ad-hoc and prepared queries that are bloating the plan cache  (Query 47) (Ad hoc Queries)\r\n",
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
                "## Get top total logical reads queries for entire instance (Query 48) (Top Logical Reads Queries)"
            ],
            "metadata": {
                "azdata_cell_guid": "0e3c4eb0-fc86-4b8d-acdd-33b1b348315c"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Get top total logical reads queries for entire instance (Query 48) (Top Logical Reads Queries)\r\n",
                "SELECT TOP(50) DB_NAME(t.[dbid]) AS [Database Name],\r\n",
                "REPLACE(REPLACE(LEFT(t.[text], 255), CHAR(10),''), CHAR(13),'') AS [Short Query Text], \r\n",
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
                "qs.execution_count AS [Execution Count], \r\n",
                "CASE WHEN CONVERT(nvarchar(max), qp.query_plan) COLLATE Latin1_General_BIN2 LIKE N'%<MissingIndexes>%' THEN 1 ELSE 0 END AS [Has Missing Index],\r\n",
                "qs.creation_time AS [Creation Time]\r\n",
                "--,t.[text] AS [Complete Query Text], qp.query_plan AS [Query Plan] -- uncomment out these columns if not copying results to Excel\r\n",
                "FROM sys.dm_exec_query_stats AS qs WITH (NOLOCK)\r\n",
                "CROSS APPLY sys.dm_exec_sql_text(plan_handle) AS t \r\n",
                "CROSS APPLY sys.dm_exec_query_plan(plan_handle) AS qp \r\n",
                "ORDER BY qs.total_logical_reads DESC OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "d6b16f1e-37b5-4e39-81c9-e50678c61245",
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
                "## Get top average elapsed time queries for entire instance (Query 49) (Top Avg Elapsed Time Queries)"
            ],
            "metadata": {
                "azdata_cell_guid": "15ea813a-a0d7-4718-a194-61fe13f68453"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Get top average elapsed time queries for entire instance (Query 49) (Top Avg Elapsed Time Queries)\r\n",
                "SELECT TOP(50) DB_NAME(t.[dbid]) AS [Database Name], \r\n",
                "REPLACE(REPLACE(LEFT(t.[text], 255), CHAR(10),''), CHAR(13),'') AS [Short Query Text],  \r\n",
                "qs.total_elapsed_time/qs.execution_count AS [Avg Elapsed Time],\r\n",
                "qs.min_elapsed_time, qs.max_elapsed_time, qs.last_elapsed_time,\r\n",
                "qs.execution_count AS [Execution Count],  \r\n",
                "qs.total_logical_reads/qs.execution_count AS [Avg Logical Reads], \r\n",
                "qs.total_physical_reads/qs.execution_count AS [Avg Physical Reads], \r\n",
                "qs.total_worker_time/qs.execution_count AS [Avg Worker Time],\r\n",
                "CASE WHEN CONVERT(nvarchar(max), qp.query_plan) COLLATE Latin1_General_BIN2 LIKE N'%<MissingIndexes>%' THEN 1 ELSE 0 END AS [Has Missing Index],\r\n",
                "qs.creation_time AS [Creation Time]\r\n",
                "--,t.[text] AS [Complete Query Text], qp.query_plan AS [Query Plan] -- uncomment out these columns if not copying results to Excel\r\n",
                "FROM sys.dm_exec_query_stats AS qs WITH (NOLOCK)\r\n",
                "CROSS APPLY sys.dm_exec_sql_text(plan_handle) AS t \r\n",
                "CROSS APPLY sys.dm_exec_query_plan(plan_handle) AS qp \r\n",
                "ORDER BY qs.total_elapsed_time/qs.execution_count DESC OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "3372c7e9-a778-4f48-9e37-751a9511bd42",
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
                "Helps you find the highest average elapsed time queries across the entire instance\r\n",
                "- Can also help track down parameter sniffing issues"
            ],
            "metadata": {
                "azdata_cell_guid": "6d559a6d-2736-43e1-a294-2c81ed6339c0"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Look at UDF execution statistics (Query 50) (UDF Stats by DB)"
            ],
            "metadata": {
                "azdata_cell_guid": "1f3a49be-1fc5-4674-a450-9c7c59ef2d4f"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Look at UDF execution statistics (Query 50) (UDF Stats by DB)\r\n",
                "SELECT TOP (25) DB_NAME(database_id) AS [Database Name], \r\n",
                "\t\t   OBJECT_NAME(object_id, database_id) AS [Function Name],\r\n",
                "\t\t   total_worker_time, execution_count, total_elapsed_time,  \r\n",
                "           total_elapsed_time/execution_count AS [avg_elapsed_time],  \r\n",
                "           last_elapsed_time, last_execution_time, cached_time, [type_desc] \r\n",
                "FROM sys.dm_exec_function_stats WITH (NOLOCK) \r\n",
                "ORDER BY total_worker_time DESC OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "b5d74b0b-2a19-4359-a39d-6f48babc9415",
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
                "[sys.dm_exec_function_stats (Transact-SQL)](https://bit.ly/2q1Q6BM)\r\n",
                "\r\n",
                "[Showplan Enhancements for UDFs](https://bit.ly/2LVqiQ1)"
            ],
            "metadata": {
                "azdata_cell_guid": "867a3ce4-b2d4-4bbb-a3e9-9a997f00b21a"
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
                "## Individual File Sizes and space available for current database  (Query 51) (File Sizes and Space)"
            ],
            "metadata": {
                "azdata_cell_guid": "44dc42a9-0712-490c-a7d3-436cc3aad079"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Individual File Sizes and space available for current database  (Query 51) (File Sizes and Space)\r\n",
                "SELECT f.name AS [File Name] , f.physical_name AS [Physical Name], \r\n",
                "CAST((f.size/128.0) AS DECIMAL(15,2)) AS [Total Size in MB],\r\n",
                "CAST(f.size/128.0 - CAST(FILEPROPERTY(f.name, 'SpaceUsed') AS int)/128.0 AS DECIMAL(15,2)) \r\n",
                "AS [Available Space In MB],\r\n",
                "CAST((f.size/128.0) AS DECIMAL(15,2)) - \r\n",
                "CAST(f.size/128.0 - CAST(FILEPROPERTY(f.name, 'SpaceUsed') AS int)/128.0 AS DECIMAL(15,2)) AS [Used Space in MB],\r\n",
                "f.[file_id], fg.name AS [Filegroup Name],\r\n",
                "f.is_percent_growth, f.growth, fg.is_default, fg.is_read_only, \r\n",
                "fg.is_autogrow_all_files\r\n",
                "FROM sys.database_files AS f WITH (NOLOCK) \r\n",
                "LEFT OUTER JOIN sys.filegroups AS fg WITH (NOLOCK)\r\n",
                "ON f.data_space_id = fg.data_space_id\r\n",
                "ORDER BY f.[file_id] OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "afab3607-97d0-406c-829f-e4eee79b1ee9",
                "tags": []
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
                "## Log space usage for current database  (Query 52) (Log Space Usage)"
            ],
            "metadata": {
                "azdata_cell_guid": "d18709d8-7651-46a0-b69a-dd4b656f459d"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Log space usage for current database  (Query 52) (Log Space Usage)\r\n",
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
                "## Status of last VLF for current database  (Query 53) (Last VLF Status)"
            ],
            "metadata": {
                "azdata_cell_guid": "a1d08900-e245-45cd-999d-182449b9adf0"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Status of last VLF for current database  (Query 53) (Last VLF Status)\r\n",
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
                "## Get database scoped configuration values for current database (Query 54) (Database-scoped Configurations)"
            ],
            "metadata": {
                "azdata_cell_guid": "454ec670-3a7a-462b-8d48-cdcad3ec052f"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Get database scoped configuration values for current database (Query 54) (Database-scoped Configurations)\r\n",
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
                "## I/O Statistics by file for the current database  (Query 55) (IO Stats By File)"
            ],
            "metadata": {
                "azdata_cell_guid": "0f37264e-c938-4288-8ae0-0758acd3c24d"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- I/O Statistics by file for the current database  (Query 55) (IO Stats By File)\r\n",
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
                "## Get most frequently executed queries for this database (Query 56) (Query Execution Counts)"
            ],
            "metadata": {
                "azdata_cell_guid": "3cea974b-f126-4cab-86fc-4ce7e006de36"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Get most frequently executed queries for this database (Query 56) (Query Execution Counts)\r\n",
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
                "## **Queries 57 through 62 are the \"Bad Man List\" for stored procedures**"
            ],
            "metadata": {
                "azdata_cell_guid": "a79de6e1-5d2f-4608-b282-8fa000b0c8a1"
            }
        },
        {
            "cell_type": "markdown",
            "source": [
                "## Top Cached SPs By Execution Count (Query 57) (SP Execution Counts)"
            ],
            "metadata": {
                "azdata_cell_guid": "49f07abb-c2ca-418d-9b03-05d76604658a"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Top Cached SPs By Execution Count (Query 57) (SP Execution Counts)\r\n",
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
                "## Top Cached SPs By Avg Elapsed Time (Query 58) (SP Avg Elapsed Time)"
            ],
            "metadata": {
                "azdata_cell_guid": "d9d2dbfa-d50b-4758-9727-9a2bb85f114b"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Top Cached SPs By Avg Elapsed Time (Query 58) (SP Avg Elapsed Time)\r\n",
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
                "## Top Cached SPs By Total Worker time. Worker time relates to CPU cost  (Query 59) (SP Worker Time)"
            ],
            "metadata": {
                "azdata_cell_guid": "62d3d97f-4f28-430f-870f-8f5d2710665a"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Top Cached SPs By Total Worker time. Worker time relates to CPU cost  (Query 59) (SP Worker Time)\r\n",
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
                "## Top Cached SPs By Total Logical Reads. Logical reads relate to memory pressure  (Query 60) (SP Logical Reads)"
            ],
            "metadata": {
                "azdata_cell_guid": "0c5f4b2b-0f1e-4b6b-b3ef-a0a4289255cb"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Top Cached SPs By Total Logical Reads. Logical reads relate to memory pressure  (Query 60) (SP Logical Reads)\r\n",
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
                "## Top Cached SPs By Total Physical Reads. Physical reads relate to disk read I/O pressure  (Query 61) (SP Physical Reads)"
            ],
            "metadata": {
                "azdata_cell_guid": "4cb0b8cf-ac19-4062-90f8-46c0f1b99d13"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Top Cached SPs By Total Physical Reads. Physical reads relate to disk read I/O pressure  (Query 61) (SP Physical Reads)\r\n",
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
                "## Top Cached SPs By Total Logical Writes (Query 62) (SP Logical Writes)"
            ],
            "metadata": {
                "azdata_cell_guid": "24fb6506-9956-4708-b9ad-77d1ce74233c"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Top Cached SPs By Total Logical Writes (Query 62) (SP Logical Writes)\r\n",
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
                "## Lists the top statements by average input/output usage for the current database  (Query 63) (Top IO Statements)"
            ],
            "metadata": {
                "azdata_cell_guid": "9b89a916-a359-4328-a297-94914d05b4ff"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Lists the top statements by average input/output usage for the current database  (Query 63) (Top IO Statements)\r\n",
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
                "## Possible Bad NC Indexes (writes > reads)  (Query 64) (Bad NC Indexes)"
            ],
            "metadata": {
                "azdata_cell_guid": "015decc0-fce5-4334-9afd-7ca74087bac0"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Possible Bad NC Indexes (writes > reads)  (Query 64) (Bad NC Indexes)\r\n",
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
                "## Missing Indexes for current database by Index Advantage  (Query 65) (Missing Indexes)"
            ],
            "metadata": {
                "azdata_cell_guid": "533323aa-8cb7-4093-8d82-93d0090ec47d"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Missing Indexes for current database by Index Advantage  (Query 65) (Missing Indexes)\r\n",
                "SELECT DISTINCT CONVERT(decimal(18,2), migs.user_seeks * migs.avg_total_user_cost * (migs.avg_user_impact * 0.01)) AS [index_advantage], \r\n",
                "migs.last_user_seek, mid.[statement] AS [Database.Schema.Table],\r\n",
                "mid.equality_columns, mid.inequality_columns, mid.included_columns,\r\n",
                "migs.user_seeks, migs.avg_total_user_cost, migs.avg_user_impact,\r\n",
                "OBJECT_NAME(mid.[object_id]) AS [Table Name], p.rows AS [Table Rows]\r\n",
                "FROM sys.dm_db_missing_index_group_stats AS migs WITH (NOLOCK)\r\n",
                "INNER JOIN sys.dm_db_missing_index_groups AS mig WITH (NOLOCK)\r\n",
                "ON migs.group_handle = mig.index_group_handle\r\n",
                "INNER JOIN sys.dm_db_missing_index_details AS mid WITH (NOLOCK)\r\n",
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
                "## Find missing index warnings for cached plans in the current database  (Query 66) (Missing Index Warnings)"
            ],
            "metadata": {
                "azdata_cell_guid": "642e72dd-3375-470f-a36d-6a5e40151c0a"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Find missing index warnings for cached plans in the current database  (Query 66) (Missing Index Warnings)\r\n",
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
                "## Breaks down buffers used by current database by object (table, index) in the buffer cache  (Query 67) (Buffer Usage)"
            ],
            "metadata": {
                "azdata_cell_guid": "b8719781-9935-47fe-9cce-1475fd0c5dde"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Get Table names, row counts, and compression status for clustered index or heap  (Query 67) (Table Sizes)\r\n",
                "SELECT fg.name AS [Filegroup Name], SCHEMA_NAME(o.Schema_ID) AS [Schema Name],\r\n",
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
                "INNER JOIN sys.database_files AS f WITH (NOLOCK)\r\n",
                "ON b.file_id = f.file_id\r\n",
                "INNER JOIN sys.filegroups AS fg WITH (NOLOCK)\r\n",
                "ON f.data_space_id = fg.data_space_id\r\n",
                "WHERE b.database_id = CONVERT(int, DB_ID())\r\n",
                "AND p.[object_id] > 100\r\n",
                "AND OBJECT_NAME(p.[object_id]) NOT LIKE N'plan_%'\r\n",
                "AND OBJECT_NAME(p.[object_id]) NOT LIKE N'sys%'\r\n",
                "AND OBJECT_NAME(p.[object_id]) NOT LIKE N'xml_index_nodes%'\r\n",
                "GROUP BY fg.name, o.Schema_ID, p.[object_id], p.index_id, \r\n",
                "         p.data_compression_desc, p.[Rows]\r\n",
                "ORDER BY [BufferCount] DESC OPTION (RECOMPILE);"
            ],
            "metadata": {
                "azdata_cell_guid": "e24ea355-502e-4e1a-b17c-1c5e67d930d4",
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
                "## Get Table names, row counts, and compression status for clustered index or heap  (Query 68) (Table Sizes)"
            ],
            "metadata": {
                "azdata_cell_guid": "0180bfe5-9ef8-4155-95e5-1014e1ba6b2f"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Get Table names, row counts, and compression status for clustered index or heap  (Query 68) (Table Sizes)\r\n",
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
                "## Get some key table properties (Query 69) (Table Properties)"
            ],
            "metadata": {
                "azdata_cell_guid": "f4afcbe8-bbfe-43c6-b394-5acf2002c590"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Get some key table properties (Query 69) (Table Properties)\r\n",
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
                "## When were Statistics last updated on all indexes?  (Query 70) (Statistics Update)"
            ],
            "metadata": {
                "azdata_cell_guid": "8f276f88-0917-4dfd-b558-362066d8b3af"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- When were Statistics last updated on all indexes?  (Query 70) (Statistics Update)\r\n",
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
                "## Look at most frequently modified indexes and statistics (Query 71) (Volatile Indexes)"
            ],
            "metadata": {
                "azdata_cell_guid": "1c6607f6-bb73-48cd-bd31-3d265f109012"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Look at most frequently modified indexes and statistics (Query 71) (Volatile Indexes)\r\n",
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
                "## Get fragmentation info for all indexes above a certain size in the current database  (Query 72) (Index Fragmentation)"
            ],
            "metadata": {
                "azdata_cell_guid": "9031de0d-fc38-4219-8a88-9728f0ebc79d"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Get fragmentation info for all indexes above a certain size in the current database  (Query 72) (Index Fragmentation)\r\n",
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
                "## Index Read/Write stats (all tables in current DB) ordered by Reads  (Query 73) (Overall Index Usage - Reads)"
            ],
            "metadata": {
                "azdata_cell_guid": "1a3ff6ab-165b-411d-8baf-713b6f322dc2"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "--- Index Read/Write stats (all tables in current DB) ordered by Reads  (Query 73) (Overall Index Usage - Reads)\r\n",
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
                "## Index Read/Write stats (all tables in current DB) ordered by Writes  (Query 74) (Overall Index Usage - Writes)"
            ],
            "metadata": {
                "azdata_cell_guid": "a3dafd2f-5693-492e-8e7b-f558c4ec624e"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "--- Index Read/Write stats (all tables in current DB) ordered by Writes  (Query 74) (Overall Index Usage - Writes)\r\n",
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
                "## Get in-memory OLTP index usage (Query 75) (XTP Index Usage)"
            ],
            "metadata": {
                "azdata_cell_guid": "7fb895d5-7d7c-49d1-b459-bea8648eee59"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Get in-memory OLTP index usage (Query 75) (XTP Index Usage)\r\n",
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
                "## Look at Columnstore index physical statistics (Query 76) (Columnstore Index Physical Stat)"
            ],
            "metadata": {
                "azdata_cell_guid": "f708aa73-505b-4aaa-9c7a-f1ed5c8b2366"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Look at Columnstore index physical statistics (Query 76) (Columnstore Index Physical Stat)\r\n",
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
                "## Get lock waits for current database (Query 77) (Lock Waits)"
            ],
            "metadata": {
                "azdata_cell_guid": "58df2dd4-b3ff-4947-9cef-407ff9d74ca2"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Get lock waits for current database (Query 77) (Lock Waits)\r\n",
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
                "## Look at UDF execution statistics (Query 78) (UDF Statistics)"
            ],
            "metadata": {
                "azdata_cell_guid": "4bc1f2be-a361-4e8c-a11f-43a8b9d31278"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Look at UDF execution statistics (Query 78) (UDF Statistics)\r\n",
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
                "## Get QueryStore Options for this database (Query 79) (QueryStore Options)"
            ],
            "metadata": {
                "azdata_cell_guid": "04fecb8a-6fa8-4aae-9cc0-22f4aa0419e4"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Get QueryStore Options for this database (Query 79) (QueryStore Options)\r\n",
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
                "## Get input buffer information for the current database (Query 80) (Input Buffer)"
            ],
            "metadata": {
                "azdata_cell_guid": "414cd580-c270-4284-a0e9-dc913d5003d3"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Get input buffer information for the current database (Query 80) (Input Buffer)\r\n",
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
                "## Get any resumable index rebuild operation information (Query 81) (Resumable Index Rebuild)"
            ],
            "metadata": {
                "azdata_cell_guid": "db25476b-da67-4b59-accb-1d426a1bfa5d"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Get any resumable index rebuild operation information (Query 81) (Resumable Index Rebuild)\r\n",
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
                "## Get database automatic tuning options (Query 82) (Automatic Tuning Options)"
            ],
            "metadata": {
                "azdata_cell_guid": "5b5aa22a-ec08-4883-9ba3-5b493dcfad62"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Get database automatic tuning options (Query 82) (Automatic Tuning Options)\r\n",
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
                "## Look at recent Full backups for the current database (Query 83) (Recent Full Backups)"
            ],
            "metadata": {
                "azdata_cell_guid": "d419108a-d2fc-41a7-9524-6c42038ab4a8"
            }
        },
        {
            "cell_type": "code",
            "source": [
                "-- Look at recent Full backups for the current database (Query 83) (Recent Full Backups)\r\n",
                "SELECT TOP (30) bs.machine_name, bs.server_name, bs.database_name AS [Database Name], bs.recovery_model,\r\n",
                "CONVERT (BIGINT, bs.backup_size / 1048576 ) AS [Uncompressed Backup Size (MB)],\r\n",
                "CONVERT (BIGINT, bs.compressed_backup_size / 1048576 ) AS [Compressed Backup Size (MB)],\r\n",
                "CONVERT (NUMERIC (20,2), (CONVERT (FLOAT, bs.backup_size) /\r\n",
                "CONVERT (FLOAT, bs.compressed_backup_size))) AS [Compression Ratio], bs.has_backup_checksums, bs.is_copy_only, bs.encryptor_type,\r\n",
                "DATEDIFF (SECOND, bs.backup_start_date, bs.backup_finish_date) AS [Backup Elapsed Time (sec)],\r\n",
                "bs.backup_finish_date AS [Backup Finish Date], bmf.physical_device_name AS [Backup Location], bmf.physical_block_size\r\n",
                "FROM msdb.dbo.backupset AS bs WITH (NOLOCK)\r\n",
                "INNER JOIN msdb.dbo.backupmediafamily AS bmf WITH (NOLOCK)\r\n",
                "ON bs.media_set_id = bmf.media_set_id  \r\n",
                "WHERE bs.database_name = DB_NAME(DB_ID())\r\n",
                "AND bs.[type] = 'D' -- Change to L if you want Log backups\r\n",
                "ORDER BY bs.backup_finish_date DESC OPTION (RECOMPILE);"
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
                "Things to look at:\r\n",
                "- Are your backup sizes and times changing over time?\r\n",
                "- Are you using backup compression?\r\n",
                "- Are you using backup checksums?\r\n",
                "- Are you doing copy_only backups?\r\n",
                "- Are you doing encrypted backups?\r\n",
                "- Have you done any backup tuning with striped backups, or changing the parameters of the backup command?\r\n",
                "- Where are the backups going to?\r\n",
                "\r\n",
                "In SQL Server 2016, native SQL Server backup compression [actually works much better](https://bit.ly/28Rpb2x) with databases that are using TDE than in previous versions"
            ],
            "metadata": {
                "azdata_cell_guid": "bea45ff6-935f-4849-ae99-0f55bada6386"
            }
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