function Invoke-DbaDatabaseCorruption {
<#
    .SYNOPSIS
    Utilizes the DBCC WRITEPAGE functionality to allow you to corrupt a specific database table for testing.  In no uncertain terms, this is a non-production command. 
    This will absolutely break your databases and that is its only purpose, please use it carefully. 
    .DESCRIPTION
    This command can be used to verify your tests for corruption are successful, and to demo various scenarios for corrupting page data.
    This command will take an instance and database (and optionally a table) and set the database to single user mode, corrupt either the specified table or the first table it finds, and returns it to multi-user.
    .PARAMETER SqlInstance
    The SQL Server instance holding the databases to be removed.You must have sysadmin access and Server version must be SQL Server version 2000 or higher.
    .PARAMETER SqlCredential
    Allows you to login to Servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:
    $cred = Get-Credential, this pass this $cred to the param. 
    Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. To connect as a different Windows user, run PowerShell as that user.
    .PARAMETER Database
    The single database you would like to corrupt, this command does not support multiple databases (on purpose.)
    .PARAMETER Table
    The specific table you want corrupted, if you do not choose one, the first user table (alphabetically) will be chosen for corruption.
    .PARAMETER WhatIf
    If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.
    .PARAMETER Confirm
    If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.
    .PARAMETER Silent
    If this switch is enabled, the internal messaging functions will be silenced.
    .NOTES
    Tags: Corruption, Testing
    Author: Constantine Kokkinos (@mobileck https://constantinekokkinos.com)
    Website: https://dbatools.io
    Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
    License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0
    .LINK
    https://dbatools.io/Invoke-DbaDatabaseCorruption
    .EXAMPLE
    Invoke-DbaDatabaseCorruption -SqlInstance sql2016 -Database containeddb
    Prompts for confirmation then selects the first table in database containeddb and corrupts it (by putting database into single user mode, writing to garbage to its first non-iam page, and returning it to multi-user.)
    .EXAMPLE
    Invoke-DbaDatabaseCorruption -SqlInstance sql2016 -Database containeddb -Table Customers -Confirm:$false
    Does not prompt and immediately corrupts table customers in database containeddb on the sql2016 instance (by putting database into single user mode, writing to garbage to its first non-iam page, and returning it to multi-user.)
#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter]$SqlInstance,
        [parameter(Mandatory = $false)]
        [Alias("Credential")]
        [PSCredential][System.Management.Automation.CredentialAttribute()]
        $SqlCredential,
        [parameter(Mandatory)]
        [string]$Database,
        [string]$Table,
        [switch]$Silent
    )
    begin {
        if ("master", "tempdb", "model", "msdb" -contains $Database) {
            Stop-Function -Message "You may not corrupt system databases."
            return
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }
        $Server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential -MinimumVersion 9

        try {
            Write-Message -Level Verbose -Message "Connecting to $SqlInstance"            
        }
        catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
        }
        
        $db = $Server.Databases | Where-Object Name -eq $Database
        
        if ($Table) {
            $tb = $db.Tables | Where-Object Name -eq $Table
        }
        else {
            $tb = $db.Tables | select -First 1
        }
        
        $RowCount = $db.Query("select top 1 * from $($tb.name)")
        
        if ($RowCount.count -eq 0) {
            Stop-Function -Message "The table $tb has no rows" -Target $table
            return
        }
        
        if (-not $tb) {
            Stop-Function -Message "There are no accessible tables in $Database on $SqlInstance." -Target $Database
            return
        }
        
        if ($Pscmdlet.ShouldProcess("$db on $SqlInstance", "Corrupt $tb")) {
            
            $clusteredindexid = $fileid = $numberofbytestochange = $bypassbufferpool = 1
            $offset = 4000
            $page = 0
            $hexvalue = '0x45'
            
            $dbccind = "DBCC IND (N'$Database',N'$($tb.Name)',$clusteredindexid)"
            # I spit on dbnull btw        
            $pages = $Server.Query($dbccind) | Where-Object { $_.IAMFID -ne [DBNull]::Value } | Select-Object -Property PageFID, PagePID -First 1
            $page = $pages.PagePID
            $fileid = $pages.PageFID
            $dbccwritepage = "DBCC WRITEPAGE (N'$Database', $fileid, $page, $offset, $numberofbytestochange, $hexvalue, $bypassbufferpool);"
            
            Write-Message -Level Verbose -Message "Settin single-user"
            
            $null = Stop-DbaProcess -SqlInstance $Server -Database $Database
            $null = Set-DbaDatabaseState -SqlServer $Server -Database $Database -SingleUser -Force
            
            
            try {
                Write-Message -Level Verbose -Message "Stopping processes"
                $null = Stop-DbaProcess -SqlInstance $Server -Database $Database
                Write-Message -Level Verbose -Message "Corrupting data"
                $Server.Databases[$Database].Query($dbccwritepage)
            }
            catch {
                $null = Set-DbaDatabaseState -SqlServer $Server -Database $Database -MultiUser -Force
                Stop-Function -Message "Failed to write page" -Category WriteError -ErrorRecord $_ -Target $instance -Continue
            }
            
            Write-Message -Level Verbose -Message "Setting multi-user"
            $Server.ConnectionContext.Disconnect() 
            $Server.ConnectionContext.Connect() 
            $null = Set-DbaDatabaseState -SqlServer $Server -Database $Database -MultiUser -Force
            
            
            [pscustomobject]@{
                ComputerName  = $Server.NetName
                InstanceName  = $Server.ServiceName
                SqlInstance   = $Server.DomainInstanceName
                Database      = $db.Name
                Table         = $tb.Name
                Status        = "Corrupted"
            }
        }
    }
}