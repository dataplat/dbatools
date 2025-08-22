function New-DbaDirectory {
    <#
    .SYNOPSIS
        Creates directories on SQL Server machines using the SQL Server service account

    .DESCRIPTION
        Creates directories on local or remote SQL Server machines by executing the xp_create_subdir extended stored procedure. This is particularly useful when you need to create backup directories, log shipping paths, or database file locations where the SQL Server service account needs to have access. The function checks if the path already exists before attempting creation and returns the success status for each operation.

    .PARAMETER SqlInstance
        The SQL Server you want to run the test on.

    .PARAMETER Path
        The Path to tests. Can be a file or directory.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Storage, Path, Directory, Folder
        Author: Stuart Moore

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires: Admin access to server (not SQL Services),
        Remoting must be enabled and accessible if $SqlInstance is not local

    .LINK
        https://dbatools.io/New-DbaDirectory

    .EXAMPLE
        PS C:\> New-DbaDirectory -SqlInstance sqlcluster -Path L:\MSAS12.MSSQLSERVER\OLAP

        If the SQL Server instance sqlcluster can create the path L:\MSAS12.MSSQLSERVER\OLAP it will do and return $true, if not it will return $false.

    .EXAMPLE
        PS C:\> $credential = Get-Credential
        PS C:\> New-DbaDirectory -SqlInstance sqlcluster -SqlCredential $credential -Path L:\MSAS12.MSSQLSERVER\OLAP

        If the SQL Server instance sqlcluster can create the path L:\MSAS12.MSSQLSERVER\OLAP it will do and return $true, if not it will return $false. Uses a SqlCredential to connect

    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory)]
        [DbaInstanceParameter[]]$SqlInstance,
        [Parameter(Mandatory)]
        [string]$Path,
        [PSCredential]$SqlCredential,
        [switch]$EnableException
    )

    foreach ($instance in $SqlInstance) {
        try {
            $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
        }

        $Path = $Path.Replace("'", "''")

        $exists = Test-DbaPath -SqlInstance $server -Path $Path

        if ($exists) {
            Stop-Function -Message "$Path already exists" -Target $server -Continue
        }

        $sql = "EXEC master.dbo.xp_create_subdir '$path'"
        Write-Message -Level Debug -Message $sql
        if ($Pscmdlet.ShouldProcess($path, "Creating a new path on $($server.name)")) {
            try {
                $null = $server.Query($sql)
                $created = $true
            } catch {
                $created = $false
                Stop-Function -Message "Failure" -ErrorRecord $_
            }

            [PSCustomObject]@{
                Server  = $instance
                Path    = $Path
                Created = $created
            }
        }
    }
}