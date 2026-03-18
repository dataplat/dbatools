function Get-DbaInstanceInstallDate {
    <#
    .SYNOPSIS
        Retrieves SQL Server installation dates by querying system tables for compliance auditing and infrastructure tracking.

    .DESCRIPTION
        Queries system tables (sys.server_principals or sysservers) to determine when SQL Server was originally installed on each target instance. This information is essential for compliance auditing, license management, and tracking hardware refresh cycles. The function automatically handles different SQL Server versions using the appropriate system table, and can optionally retrieve the Windows OS installation date through WMI for complete infrastructure documentation. Returns structured data including computer name, instance name, and precise installation timestamps.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Credential
        Windows credentials used for WMI connection when retrieving Windows OS installation date with -IncludeWindows.
        Only required when the current user lacks WMI access to the target server or when connecting across domains.

    .PARAMETER IncludeWindows
        Retrieves the Windows OS installation date in addition to SQL Server installation date using WMI.
        Useful for infrastructure audits requiring both application and operating system installation timestamps.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Install, Instance, Utility
        Author: Mitchell Hamann (@SirCaptainMitch), mitchellhamann.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaInstanceInstallDate

    .OUTPUTS
        PSCustomObject

        Returns one object per SQL Server instance with installation date information.

        Default properties (without -IncludeWindows):
        - ComputerName: The name of the computer hosting the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance format)
        - SqlInstallDate: DateTime when SQL Server was originally installed (DbaDateTime type)

        When -IncludeWindows is specified, an additional property is included:
        - WindowsInstallDate: DateTime when the Windows operating system was installed (DbaDateTime type)

        The SqlInstallDate and WindowsInstallDate properties are DbaDateTime objects that provide formatted date/time display and can be manipulated as standard datetime values. Queries sys.server_principals (SQL Server 2005+) or dbo.sysservers (SQL Server 2000) to determine installation dates.

    .EXAMPLE
        PS C:\> Get-DbaInstanceInstallDate -SqlInstance SqlBox1\Instance2

        Returns an object with SQL Instance Install date as a string.

    .EXAMPLE
        PS C:\> Get-DbaInstanceInstallDate -SqlInstance winserver\sqlexpress, sql2016

        Returns an object with SQL Instance Install date as a string for both SQLInstances that are passed to the cmdlet.

    .EXAMPLE
        PS C:\> 'sqlserver2014a', 'sql2016' | Get-DbaInstanceInstallDate

        Returns an object with SQL Instance Install date as a string for both SQLInstances that are passed to the cmdlet via the pipeline.

    .EXAMPLE
        PS C:\> Get-DbaInstanceInstallDate -SqlInstance sqlserver2014a, sql2016 -IncludeWindows

        Returns an object with the Windows Install date and the SQL install date as a string.

    .EXAMPLE
        PS C:\> Get-DbaRegServer -SqlInstance sql2014 | Get-DbaInstanceInstallDate

        Returns an object with SQL Instance install date as a string for every server listed in the Central Management Server on sql2014

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]
        $SqlCredential,
        [PSCredential]
        $Credential,
        [Switch]$IncludeWindows,
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($server.VersionMajor -ge 9) {
                Write-Message -Level Verbose -Message "Getting Install Date for: $instance"
                $sql = "SELECT create_date FROM sys.server_principals WHERE sid = 0x010100000000000512000000"
                [DbaDateTime]$sqlInstallDate = $server.Query($sql, 'master', $true).create_date
            } else {
                Write-Message -Level Verbose -Message "Getting Install Date for: $instance"
                $sql = "SELECT schemadate FROM dbo.sysservers"
                [DbaDateTime]$sqlInstallDate = $server.Query($sql, 'master', $true).schemadate
            }

            if (-not $sqlInstallDate -or $sqlInstallDate -is [System.DBNull]) {
                Write-Message -Level Verbose -Message "Trying again to get Install Date for: $instance"
                $sql = "SELECT schemadate FROM dbo.sysservers"
                [DbaDateTime]$sqlInstallDate = $server.Query($sql, 'master', $true).schemadate
            }

            $WindowsServerName = $server.ComputerNamePhysicalNetBIOS

            if ($IncludeWindows) {
                try {
                    [DbaDateTime]$windowsInstallDate = (Get-DbaCmObject -ClassName win32_OperatingSystem -ComputerName $WindowsServerName -Credential $Credential -EnableException).InstallDate
                } catch {
                    Stop-Function -Message "Failed to connect to: $WindowsServerName" -Continue -Target $instance -ErrorRecord $_
                }
            }

            $object = [PSCustomObject]@{
                ComputerName       = $server.ComputerName
                InstanceName       = $server.ServiceName
                SqlInstance        = $server.DomainInstanceName
                SqlInstallDate     = $sqlInstallDate
                WindowsInstallDate = $windowsInstallDate
            }

            if ($IncludeWindows) {
                Select-DefaultView -InputObject $object -Property ComputerName, InstanceName, SqlInstance, SqlInstallDate, WindowsInstallDate
            } else {
                Select-DefaultView -InputObject $object -Property ComputerName, InstanceName, SqlInstance, SqlInstallDate
            }

        }
    }
}