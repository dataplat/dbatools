param($ModuleName = 'dbatools')

Describe "Install-DbaWhoIsActive" -Tag "IntegrationTests" {
    BeforeAll {
        $spWhoisActive = @"
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ANSI_WARNINGS ON;
SET NUMERIC_ROUNDABORT OFF;
SET ARITHABORT ON;
GO

IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME = 'sp_WhoIsActive')
    EXEC ('CREATE PROC dbo.sp_WhoIsActive AS SELECT ''stub version, to be replaced''')
GO

/*********************************************************************************************
Who Is Active? v11.32 (2018-07-03)
(C) 2007-2018, Adam Machanic

Feedback: mailto:adam@dataeducation.com
Updates: http://whoisactive.com
Blog: http://dataeducation.com

License:
    Who is Active? is free to download and use for personal, educational, and internal
    corporate purposes, provided that this header is preserved. Redistribution or sale
    of Who is Active?, in whole or in part, is prohibited without the author's express
    written consent.
*********************************************************************************************/
ALTER PROC dbo.sp_WhoIsActive
(
--~
    --Filters--Both inclusive and exclusive
    --Set either filter to '' to disable
    --Valid filter types are: session, program, database, login, and host
    --Session is a session ID, and either 0 or '' can be used to indicate "all" sessions
    --All other filter types support % or _ as wildcards
    @filter sysname = '',
    @filter_type VARCHAR(10) = 'session',
    @not_filter sysname = '',
    @not_filter_type VARCHAR(10) = 'session',

    --Retrieve data about the calling session?
    @show_own_spid BIT = 0,

    --Retrieve data about system sessions?
    @show_system_spids BIT = 0,

    --Controls how sleeping SPIDs are handled, based on the idea of levels of interest
    --0 does not pull any sleeping SPIDs
    --1 pulls only those sleeping SPIDs that also have an open transaction
    --2 pulls all sleeping SPIDs
    @show_sleeping_spids TINYINT = 1,

    --If 1, gets the full stored procedure or running batch, when available
    --If 0, gets only the actual statement that is currently running in the batch or procedure
    @get_full_inner_text BIT = 0,

    --Get associated query plans for running tasks, if available
    --If @get_plans = 1, gets the plan based on the request's statement offset
    --If @get_plans = 2, gets the entire plan based on the request's plan_handle
    @get_plans TINYINT = 0,

    --Get the associated outer ad hoc query or stored procedure call, if available
    @get_outer_command BIT = 0,

    --Enables pulling transaction log write info and transaction duration
    @get_transaction_info BIT = 0,

    --Get information on active tasks, based on three interest levels
    --Level 0 does not pull any task-related information
    --Level 1 is a lightweight mode that pulls the top non-CXPACKET wait, giving preference to blockers
    --Level 2 pulls all available task-based metrics, including:
    --number of active tasks, current wait stats, physical I/O, context switches, and blocker information
    @get_task_info TINYINT = 1,

    --Gets associated locks for each request, aggregated in an XML format
    @get_locks BIT = 0,

    --Get average time for past runs of an active query
    --(based on the combination of plan handle, sql handle, and offset)
    @get_avg_time BIT = 0,

    --Get additional non-performance-related information about the session or request
    --text_size, language, date_format, date_first, quoted_identifier, arithabort, ansi_null_dflt_on,
    --ansi_defaults, ansi_warnings, ansi_padding, ansi_nulls, concat_null_yields_null,
    --transaction_isolation_level, lock_timeout, deadlock_priority, row_count, command_type
    --
    --If a SQL Agent job is running, an subnode called agent_info will be populated with some or all of
    --the following: job_id, job_name, step_id, step_name, msdb_query_error (in the event of an error)
    --
    --If @get_task_info is set to 2 and a lock wait is detected, a subnode called block_info will
    --be populated with some or all of the following: lock_type, database_name, object_id, file_id, hobt_id,
    --applock_hash, metadata_resource, metadata_class_id, object_name, schema_name
    @get_additional_info BIT = 0,

    --Walk the blocking chain and count the number of
    --total SPIDs blocked all the way down by a given session
    --Also enables task_info Level 1, if @get_task_info is set to 0
    @find_block_leaders BIT = 0,

    --Pull deltas on various metrics
    --Interval in seconds to wait before doing the second data pull
    @delta_interval TINYINT = 0,

    --List of desired output columns, in desired order
    --Note that the final output will be the intersection of all enabled features and all
    --columns in the list. Therefore, only columns associated with enabled features will
    --actually appear in the output. Likewise, removing columns from this list may effectively
    --disable features, even if they are turned on
    --
    --Each element in this list must be one of the valid output column names. Names must be
    --delimited by square brackets. White space, formatting, and additional characters are
    --allowed, as long as the list contains exact matches of delimited valid column names.
    @output_column_list VARCHAR(8000) = '[dd%][session_id][sql_text][sql_command][login_name][wait_info][tasks][tran_log%][cpu%][temp%][block%][reads%][writes%][context%][physical%][query_plan][locks][%]',

    --Column(s) by which to sort output, optionally with sort directions.
        --Valid column choices:
        --session_id, physical_io, reads, physical_reads, writes, tempdb_allocations,
        --tempdb_current, CPU, context_switches, used_memory, physical_io_delta, reads_delta,
        --physical_reads_delta, writes_delta, tempdb_allocations_delta, tempdb_current_delta,
        --CPU_delta, context_switches_delta, used_memory_delta, tasks, tran_start_time,
        --open_tran_count, blocking_session_id, blocked_session_count, percent_complete,
        --host_name, login_name, database_name, start_time, login_time, program_name
        --
        --Note that column names in the list must be bracket-delimited. Commas and/or white
        --space are not required.
    @sort_order VARCHAR(500) = '[start_time] ASC',

    --Formats some of the output columns in a more "human readable" form
    --0 disables outfput format
    --1 formats the output for variable-width fonts
    --2 formats the output for fixed-width fonts
    @format_output TINYINT = 1,

    --If set to a non-blank value, the script will attempt to insert into the specified
    --destination table. Please note that the script will not verify that the table exists,
    --or that it has the correct schema, before doing the insert.
    --Table can be specified in one, two, or three-part format
    @destination_table VARCHAR(4000) = '',

    --If set to 1, no data collection will happen and no result set will be returned; instead,
    --a CREATE TABLE statement will be returned via the @schema parameter, which will match
    --the schema of the result set that would be returned by using the same collection of the
    --rest of the parameters. The CREATE TABLE statement will have a placeholder token of
    --<table_name> in place of an actual table name.
    @return_schema BIT = 0,
    @schema VARCHAR(MAX) = NULL OUTPUT,

    --Help! What do I do?
    @help BIT = 0
--~
)
"@
        $testfilepath = "$env:USERPROFILE\Documents\who_MOCKED_is_active_v11_32.sql"
        $testzippath = "$env:USERPROFILE\Documents\spWhoisActive.zip"
        $DbatoolsData = Get-DbatoolsConfigValue -FullName "Path.DbatoolsData"
        $testtemp = ([System.IO.Path]::GetTempPath()).TrimEnd("\")

        Out-file -FilePath $testfilepath -Encoding utf8 -InputObject $spWhoisActive -Force
        Compress-Archive -Path $testfilepath -DestinationPath $testzippath -CompressionLevel Fastest -Force
        Compress-Archive -Path $testfilepath -DestinationPath "$testtemp\spwhoisactive.zip" -CompressionLevel Fastest -Force

        Mock -CommandName Invoke-TlsWebRequest -MockWith {
            [PSCustomObject]@{
                outerHTML = "<a href='/amachanic/sp_whoisactive/archive/v11.33.zip' rel='nofollow' class='d-flex flex-items-center'>..."
            }
        } -ParameterFilter { [string]$args -eq '-UseBasicParsing -uri https://github.com/amachanic/sp_whoisactive/releases/latest' }

        Mock -CommandName Invoke-WebRequest -MockWith { }
    }

    AfterAll {
        Remove-Item -Path $testfilepath, $testzippath, "$testtemp\who_MOCKED_is_active_v11_32.sql", "$DbatoolsData\spwhoisactive.zip" -Force -ErrorAction SilentlyContinue
        Invoke-DbaQuery -SqlInstance $global:instance1 -Database Master -Query 'DROP PROCEDURE [dbo].[sp_WhoIsActive];'
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
            $ParameterList = (Get-Command -Name $CommandName).Parameters
        }
        It "Should have SqlInstance parameter" {
            $ParameterList['SqlInstance'] | Should -Not -BeNullOrEmpty
            $ParameterList['SqlInstance'].ParameterType.FullName | Should -Be 'Dataplat.Dbatools.Parameter.DbaInstanceParameter[]'
        }
        It "Should have SqlCredential parameter" {
            $ParameterList['SqlCredential'] | Should -Not -BeNullOrEmpty
            $ParameterList['SqlCredential'].ParameterType.FullName | Should -Be 'System.Management.Automation.PSCredential'
        }
        It "Should have LocalFile parameter" {
            $ParameterList['LocalFile'] | Should -Not -BeNullOrEmpty
            $ParameterList['LocalFile'].ParameterType.FullName | Should -Be 'System.String'
        }
        It "Should have Database parameter" {
            $ParameterList['Database'] | Should -Not -BeNullOrEmpty
            $ParameterList['Database'].ParameterType.FullName | Should -Be 'System.Object'
        }
        It "Should have EnableException parameter" {
            $ParameterList['EnableException'] | Should -Not -BeNullOrEmpty
            $ParameterList['EnableException'].ParameterType.FullName | Should -Be 'System.Management.Automation.SwitchParameter'
        }
        It "Should have Force parameter" {
            $ParameterList['Force'] | Should -Not -BeNullOrEmpty
            $ParameterList['Force'].ParameterType.FullName | Should -Be 'System.Management.Automation.SwitchParameter'
        }
    }

    Context "Should Install SPWhoisActive with Mock" {
        BeforeAll {
            $results = Install-DbaWhoIsActive -SqlInstance $global:instance1 -Database Master
        }
        AfterAll {
            Invoke-DbaQuery -SqlInstance $global:instance1 -Database Master -Query 'DROP PROCEDURE [dbo].[sp_WhoIsActive];'
        }
        It "Should simulate install from internet" {
            $results | Should -Not -BeNullOrEmpty
        }
    }

    Context "Should Install SPWhoisActive from File" {
        BeforeAll {
            $results = Install-DbaWhoIsActive -SqlInstance $global:instance1 -LocalFile $testfilepath -Database Master
        }
        AfterAll {
            Invoke-DbaQuery -SqlInstance $global:instance1 -Query 'DROP PROCEDURE [dbo].[sp_WhoIsActive];'
        }
        It "Should install against .sql file" {
            $results | Should -Not -BeNullOrEmpty
        }
    }

    Context "Should Install SPWhoisActive from Zip" {
        BeforeAll {
            $results = Install-DbaWhoIsActive -SqlInstance $global:instance1 -LocalFile $testzippath -Database tempdb
        }
        AfterAll {
            Invoke-DbaQuery -SqlInstance $global:instance1 -Database tempdb -Query 'DROP PROCEDURE [dbo].[sp_WhoIsActive];'
        }
        It "Should install against ZIP" {
            $results | Should -Not -BeNullOrEmpty
        }
    }
}
