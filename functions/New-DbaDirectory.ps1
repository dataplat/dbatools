function New-DbaDirectory {
    <#
    .SYNOPSIS
        Creates new path as specified by the path variable

    .DESCRIPTION
        Uses master.dbo.xp_create_subdir to create the path
        Returns $true if the path can be created, $false otherwise

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
        Tags: Path, Directory, Folder
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
            $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
        } catch {
            Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
        }

        $Path = $Path.Replace("'", "''")

        $exists = Test-DbaPath -SqlInstance $sqlinstance -SqlCredential $SqlCredential -Path $Path

        if ($exists) {
            Stop-Function -Message "$Path already exists" -Target $server -Continue
        }

        $sql = "EXEC master.dbo.xp_create_subdir'$path'"
        Write-Message -Level Debug -Message $sql
        if ($Pscmdlet.ShouldProcess($path, "Creating a new path on $($server.name)")) {
            try {
                $null = $server.Query($sql)
                $Created = $true
            } catch {
                $Created = $false
                Stop-Function -Message "Failure" -ErrorRecord $_
            }

            [pscustomobject]@{
                Server  = $SqlInstance
                Path    = $Path
                Created = $Created
            }
        }
    }
}