function Get-DbaServerInstallDate {
    <#
    .SYNOPSIS
        Returns the install date of a SQL Instance and Windows Server.

    .DESCRIPTION
        This command returns:
        SqlInstallDate
        WindowsInstallDate (use -IncludeWindows)

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Credential object used to connect to the SQL Server using SQL Authentication as a different user

    .PARAMETER Credential
        Credential object used to connect to the SQL Server as a different Windows user

    .PARAMETER IncludeWindows
        Includes the Windows Server Install date information

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Install
        Author: Mitchell Hamann (@SirCaptainMitch), mitchellhamann.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaServerInstallDate

    .EXAMPLE
        PS C:\> Get-DbaServerInstallDate -SqlInstance SqlBox1\Instance2

        Returns an object with SQL Instance Install date as a string.

    .EXAMPLE
        PS C:\> Get-DbaServerInstallDate -SqlInstance winserver\sqlexpress, sql2016

        Returns an object with SQL Instance Install date as a string for both SQLInstances that are passed to the cmdlet.

    .EXAMPLE
        PS C:\> 'sqlserver2014a', 'sql2016' | Get-DbaServerInstallDate

        Returns an object with SQL Instance Install date as a string for both SQLInstances that are passed to the cmdlet via the pipeline.

    .EXAMPLE
        PS C:\> Get-DbaServerInstallDate -SqlInstance sqlserver2014a, sql2016 -IncludeWindows

        Returns an object with the Windows Install date and the SQL install date as a string.

    .EXAMPLE
        PS C:\> Get-DbaCmsRegServer -SqlInstance sql2014 | Get-DbaServerInstallDate

        Returns an object with SQL Instance install date as a string for every server listed in the Central Management Server on sql2014

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer", "ComputerName")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]
        $SqlCredential,
        [PSCredential]
        $Credential,
        [Switch]$IncludeWindows,
        [Alias('Silent')]
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failed to process Instance $Instance" -ErrorRecord $_ -Target $instance -Continue
            }

            if ($server.VersionMajor -ge 9) {
                Write-Message -Level Verbose -Message "Getting Install Date for: $instance"
                $sql = "SELECT create_date FROM sys.server_principals WHERE sid = 0x010100000000000512000000"
                [DbaDateTime]$sqlInstallDate = $server.Query($sql, 'master', $true).create_date

            } else {
                Write-Message -Level Verbose -Message "Getting Install Date for: $instance"
                $sql = "SELECT schemadate FROM sysservers"
                [DbaDateTime]$sqlInstallDate = $server.Query($sql, 'master', $true).create_date
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