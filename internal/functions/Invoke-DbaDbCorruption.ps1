function Invoke-DbaDbCorruption {
    <#
      .SYNOPSIS
      Utilizes the DBCC WRITEPAGE functionality  to corrupt a specific database table for testing.  In no uncertain terms, this is a non-production command.
      This will absolutely break your databases and that is its only purpose.
      Using DBCC WritePage will definitely void any support options for your database.

      .DESCRIPTION
      This command can be used to verify your tests for corruption are successful, and to demo various scenarios for corrupting page data.
      This command will take an instance and database (and optionally a table) and set the database to single user mode, corrupt either the specified table or the first table it finds, and returns it to multi-user.

      .PARAMETER SqlInstance
      The SQL Server instance holding the databases to be removed.You must have sysadmin access and Server version must be SQL Server version 2000 or higher.

      .PARAMETER SqlCredential
      Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

      .PARAMETER Database
      The single database you would like to corrupt, this command does not support multiple databases (on purpose.)

      .PARAMETER Table
      The specific table you want corrupted, if you do not choose one, the first user table (alphabetically) will be chosen for corruption.

      .PARAMETER WhatIf
      If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

      .PARAMETER Confirm
      If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

      .PARAMETER EnableException
      By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
      This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
      Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

      .NOTES
      Tags: Corruption, Testing
      Author: Constantine Kokkinos (@mobileck https://constantinekokkinos.com)
      Reference: https://www.sqlskills.com/blogs/paul/dbcc-writepage/
      Website: https://dbatools.io
      Copyright: (c) 2018 by dbatools, licensed under MIT
      License: MIT https://opensource.org/licenses/MIT

      .LINK
      https://dbatools.io/Invoke-DbaDbCorruption

      .EXAMPLE
      Invoke-DbaDbCorruption -SqlInstance sql2016 -Database containeddb
      Prompts for confirmation then selects the first table in database containeddb and corrupts it (by putting database into single user mode, writing to garbage to its first non-iam page, and returning it to multi-user.)

      .EXAMPLE
      Invoke-DbaDbCorruption -SqlInstance sql2016 -Database containeddb -Table Customers -Confirm:$false
      Does not prompt and immediately corrupts table customers in database containeddb on the sql2016 instance (by putting database into single user mode, writing to garbage to its first non-iam page, and returning it to multi-user.)
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]
        $SqlCredential,
        [parameter(Mandatory)]
        [string]$Database,
        [string]$Table,
        [switch]$EnableException
    )
    # For later if we want to do bit flipping.
    # function Dbcc-ReadPage {
    #   param (
    #     $SqlInstance,
    #     $Database,
    #     $TableName,
    #     $IndexID = 1
    #   )
    #   $DbccPage = "DBCC PAGE (N'$Database',N'$($TableName)',$IndexID)"
    #   Write-Message -Level Verbose -Message "$DbccPage"
    #   $pages = $SqlInstance.Query($DbccPage) | Where-Object { $_.IAMFID -ne [DBNull]::Value }
    #   return $Pages
    # }

    function Dbcc-Index {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseApprovedVerbs", "")]
        [CmdletBinding()]
        param (
            $SqlInstance,
            $Database,
            $TableName,
            $IndexID = 1
        )
        $DbccInd = "DBCC IND (N'$Database',N'$($TableName)',$IndexID)"
        Write-Message -Level Verbose -Message "$DbccInd"
        $pages = $SqlInstance.Query($DbccInd) | Where-Object { $_.IAMFID -ne [DBNull]::Value }
        return $Pages
    }
    function Dbcc-WritePage {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseApprovedVerbs", "")]
        [CmdletBinding()]
        param (
            $SqlInstance,
            $Database,
            $FileId = 1,
            $PageId,
            $Offset = 4000,
            $NumberOfBytesToChange = 1,
            $HexString = '0x45',
            $bypassbufferpool = 1
        )
        $DbccWritePage = "DBCC WRITEPAGE (N'$Database', $FileId, $PageId, $Offset, $NumberOfBytesToChange, $HexString, $bypassbufferpool);"
        Write-Message -Level Verbose -Message "$DbccWritePage"
        $WriteInfo = $SqlInstance.Databases[$Database].Query($DbccWritePage)
        return $WriteInfo
    }

    if ("master", "tempdb", "model", "msdb" -contains $Database) {
        Stop-Function -EnableException:$EnableException -Message "You may not corrupt system databases."
        return
    }

    try {
        $Server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential -MinimumVersion 9
    } catch {
        Stop-Function -EnableException:$EnableException -Message "Error occurred while establishing connection to $SqlInstance" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance
        return
    }

    $db = $Server.Databases | Where-Object { $_.Name -eq $Database }
    if (!$db) {
        Stop-Function -EnableException:$EnableException -Message "The database specified does not exist."
        return
    }
    if ($Table) {
        $tb = $db.Tables | Where-Object Name -eq $Table
    } else {
        $tb = $db.Tables | Select-Object -First 1
    }

    if (-not $tb) {
        Stop-Function -EnableException:$EnableException -Message "There are no accessible tables in $Database on $SqlInstance." -Target $Database
        return
    }

    $RowCount = $db.Query("select top 1 * from $($tb.name)")
    if ($RowCount.count -eq 0) {
        Stop-Function -EnableException:$EnableException -Message "The table $tb has no rows" -Target $table
        return
    }

    if ($Pscmdlet.ShouldProcess("$db on $SqlInstance", "Corrupt $tb in $Database")) {
        $pages = Dbcc-Index -SqlInstance $Server -Database $Database -TableName $tb.Name | Select-Object -First 1
        #Dbcc-ReadPage -SqlInstance $Server -Database $Database -PageId $pages.PagePID -FileId $pages.PageFID
        Write-Message -Level Verbose -Message "Setting single-user mode."
        $null = Stop-DbaProcess -SqlInstance $Server -Database $Database
        $null = Set-DbaDbState -SqlInstance $Server -Database $Database -SingleUser -Force

        try {
            Write-Message -Level Verbose -Message "Stopping processes in target database."
            $null = Stop-DbaProcess -SqlInstance $Server -Database $Database
            Write-Message -Level Verbose -Message "Corrupting data."
            Dbcc-WritePage -SqlInstance $Server -Database $Database -PageId $pages.PagePID -FileId $pages.PageFID
        } catch {
            $Server.ConnectionContext.Disconnect()
            $Server.ConnectionContext.Connect()
            $null = Set-DbaDbState -SqlInstance $Server -Database $Database -MultiUser -Force
            Stop-Function -EnableException:$EnableException -Message "Failed to write page" -Category WriteError -ErrorRecord $_ -Target $instance
            return
        }

        Write-Message -Level Verbose -Message "Setting database into multi-user mode."
        # If you do not disconnect and reconnect, multiuser fails.
        $Server.ConnectionContext.Disconnect()
        $Server.ConnectionContext.Connect()
        $null = Set-DbaDbState -SqlInstance $Server -Database $Database -MultiUser -Force

        [pscustomobject]@{
            ComputerName = $Server.ComputerName
            InstanceName = $Server.ServiceName
            SqlInstance  = $Server.DomainInstanceName
            Database     = $db.Name
            Table        = $tb.Name
            Status       = "Corrupted"
        }
    }
}