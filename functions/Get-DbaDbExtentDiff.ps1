function Get-DbaDbExtentDiff {
    <#
        .SYNOPSIS
            What percentage of a database has changed since the last full backup

        .DESCRIPTION
            This is only an implementation of the script created by Paul S. Randal to find what percentage of a database has changed since the last full backup
            https://www.sqlskills.com/blogs/paul/new-script-how-much-of-the-database-has-changed-since-the-last-full-backup/

        .PARAMETER SqlInstance
            The target SQL Server instance

        .PARAMETER SqlCredential
            Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:
            $scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.
            To connect as a different Windows user, run PowerShell as that user.

        .PARAMETER Database
            The database where the script will be installed. Defaults to master

        .PARAMETER WhatIf
            Shows what would happen if the command were to run. No actions are actually performed.

        .PARAMETER Confirm
            Prompts you for confirmation before executing any changing operations within the command.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Author: Viorel Ciucu, viorel.ciucu@gmail.com, cviorel.com

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            http://dbatools.io/Get-DbaDbExtentDiff

        .EXAMPLE
            Install the objects in master and msdb database
            Get-DbaDbExtentDiff -SqlInstance RES14224

        .EXAMPLE
            Install the objects in [DBA] database
            Get-DbaDbExtentDiff -SqlInstance RES14224 -Database DBA

    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias('ServerInstance', 'SqlServer')]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object]$Database = "master",
        [switch][Alias('Silent')]$EnableException
    )

    process {

        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance"
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -NonPooled
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            $SQLskillsDIFForFULL = "
                IF EXISTS (SELECT * FROM sys.objects WHERE NAME = N'SQLskillsConvertToExtents')
                DROP FUNCTION [SQLskillsConvertToExtents];
                GO

                CREATE FUNCTION [SQLskillsConvertToExtents] (
                @extents    VARCHAR (100))
                RETURNS INTEGER
                AS
                BEGIN
                DECLARE @extentTotal    INT;
                DECLARE @colon          INT;

                DECLARE @firstExtent    INT;
                DECLARE @secondExtent   INT;

                SET @extentTotal = 0;
                SET @colon = CHARINDEX (':', @extents);

                IF (CHARINDEX (':', @extents, @colon + 1) = 0)
                SET @extentTotal = 1;
                ELSE
                BEGIN
                SET @firstExtent = CONVERT (INT,
                SUBSTRING (@extents, @colon + 1, CHARINDEX (')', @extents, @colon) - @colon - 1));
                SET @colon = CHARINDEX (':', @extents, @colon + 1);
                SET @secondExtent = CONVERT (INT,
                SUBSTRING (@extents, @colon + 1, CHARINDEX (')', @extents, @colon) - @colon - 1));
                SET @extentTotal = (@secondExtent - @firstExtent) / 8 + 1;
                END

                RETURN @extentTotal;
                END;
                GO

                IF OBJECT_ID (N'sp_SQLskillsDIFForFULL') IS NOT NULL
                DROP PROCEDURE [sp_SQLskillsDIFForFULL];
                GO

                CREATE PROCEDURE [sp_SQLskillsDIFForFULL] (
                @dbName SYSNAME)
                AS
                BEGIN
                SET NOCOUNT ON;

                IF EXISTS (SELECT * FROM [tempdb].[sys].[objects] WHERE NAME = N'SQLskillsDBCCPage')
                DROP TABLE [tempdb].[dbo].[SQLskillsDBCCPage];

                CREATE TABLE tempdb.dbo.SQLskillsDBCCPage (
                [ParentObject]  VARCHAR (100),
                [Object]        VARCHAR (100),
                [Field]         VARCHAR (100),
                [VALUE]         VARCHAR (100));

                DECLARE @fileID          INT;
                DECLARE @fileSizePages   INT;
                DECLARE @extentID        INT;
                DECLARE @pageID          INT;
                DECLARE @DIFFTotal       BIGINT;
                DECLARE @sizeTotal       BIGINT;
                DECLARE @total           BIGINT;
                DECLARE @dbccPageString  VARCHAR (200);

                SELECT @DIFFtotal = 0;
                SELECT @sizeTotal = 0;

                DECLARE [files] CURSOR FOR
                SELECT [file_id], [size] FROM master.sys.master_files
                WHERE [type_desc] = N'ROWS'
                AND [state_desc] = N'ONLINE'
                AND [database_id] = DB_ID (@dbName);

                OPEN files;

                FETCH NEXT FROM [files] INTO @fileID, @fileSizePages;

                WHILE @@FETCH_STATUS = 0
                BEGIN
                SELECT @extentID = 0;

                SELECT @sizeTotal = @sizeTotal + @fileSizePages / 8;

                WHILE (@extentID < @fileSizePages)
                BEGIN
                SELECT @pageID = @extentID + 6;

                SELECT @dbccPageString = 'DBCC PAGE (['
                + @dbName + '], '
                + CAST (@fileID AS VARCHAR) + ', '
                + CAST (@pageID AS VARCHAR) + ', 3) WITH TABLERESULTS, NO_INFOMSGS';

                TRUNCATE TABLE [tempdb].[dbo].[SQLskillsDBCCPage];
                INSERT INTO [tempdb].[dbo].[SQLskillsDBCCPage] EXEC (@dbccPageString);

                SELECT @total = SUM ([tempdb].[dbo].[SQLskillsConvertToExtents] ([Field]))
                FROM [tempdb].[dbo].[SQLskillsDBCCPage]
                WHERE [VALUE] = '    CHANGED'
                AND [ParentObject] LIKE 'DIFF_MAP%';

                SET @DIFFtotal = @DIFFtotal + @total;

                SET @extentID = @extentID + 511232;
                END

                FETCH NEXT FROM [files] INTO @fileID, @fileSizePages;
                END;

                DROP TABLE [tempdb].[dbo].[SQLskillsDBCCPage];
                CLOSE [files];
                DEALLOCATE [files];

                SELECT
                @sizeTotal AS [Total Extents],
                @DIFFtotal AS [Changed Extents],
                ROUND (
                (CONVERT (FLOAT, @DIFFtotal) /
                CONVERT (FLOAT, @sizeTotal)) * 100, 2) AS [Percentage Changed];
                END;
                GO
            "

            $parsedQuery = @()
            foreach ($line in $SQLskillsDIFForFULL) {
                $line = $line -replace '(^\s+|\s+$)', ''
                $line = $line -replace "`t", ''
                $parsedQuery += $line + "`r`n"
            }

            try {
                Write-Message -Level Output -Message "Executing on server $SqlInstance, database $Database"
                foreach ($query in ($parsedQuery -Split "\nGO\b")) {
                    $null = Invoke-DbaSqlCmd -ServerInstance $instance -Query $query -Credential $SqlCredential -Database tempdb
                }
            }
            catch {
            }	 

            $db = $server.Databases[$Database]
            $runIt = "EXEC [tempdb].[dbo].[sp_SQLskillsDIFForFULL] N`'" + $Database + "`'"
            $cleanIt = "
                IF OBJECT_ID (N'sp_SQLskillsDIFForFULL') IS NOT NULL
                    DROP PROCEDURE [sp_SQLskillsDIFForFULL];
                IF EXISTS (SELECT * FROM sys.objects WHERE NAME = N'SQLskillsConvertToExtents')
                    DROP FUNCTION [SQLskillsConvertToExtents];
            "
            try {
                $result = $db.Query($runIt)
                Add-Member -InputObject $result -Name ComputerName -MemberType NoteProperty -Value $instance.ComputerName
                Add-Member -InputObject $result -Name InstanceName -MemberType NoteProperty -Value $instance.InstanceName
                Add-Member -InputObject $result -Name Database -MemberType NoteProperty -Value $Database
                $defaults = 'ComputerName', 'InstanceName', 'Database', 'Total Extents', 'Changed Extents', 'Percentage Changed'
                Select-DefaultView -InputObject $result -Property $defaults
            }
            catch {
                Stop-Function -Message "Could not execute $query in $Database on $instance" -ErrorRecord $_ -Target $db -Continue
            }	

            # Cleanup
            try {
                $null = Invoke-DbaSqlCmd -ServerInstance $instance -Query $cleanIt -Credential $SqlCredential -Database tempdb
            }
            catch {
                Stop-Function -Message "Could not execute $query in $Database on $instance" -ErrorRecord $_ -Target $db -Continue
            }
        }
    }
}