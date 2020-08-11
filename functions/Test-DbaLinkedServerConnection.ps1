function Test-DbaLinkedServerConnection {
    <#
    .SYNOPSIS
        Test all linked servers from the sql servers passed

    .DESCRIPTION
        Test each linked server on the instance

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.

        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: LinkedServer
        Author: Thomas LaRock ( https://thomaslarock.com )

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Test-DbaLinkedServerConnection

    .EXAMPLE
        PS C:\> Test-DbaLinkedServerConnection -SqlInstance DEV01

        Test all Linked Servers for the SQL Server instance DEV01

    .EXAMPLE
        PS C:\> Test-DbaLinkedServerConnection -SqlInstance sql2016 | Out-File C:\temp\results.txt

        Test all Linked Servers for the SQL Server instance sql2016 and output results to file

    .EXAMPLE
        PS C:\> Test-DbaLinkedServerConnection -SqlInstance sql2016, sql2014, sql2012

        Test all Linked Servers for the SQL Server instances sql2016, sql2014 and sql2012

    .EXAMPLE
        PS C:\> $servers = "sql2016","sql2014","sql2012"
        PS C:\> $servers | Test-DbaLinkedServerConnection -SqlCredential sqladmin

        Test all Linked Servers for the SQL Server instances sql2016, sql2014 and sql2012 using SQL login credentials

    .EXAMPLE
        PS C:\> $servers = "sql2016","sql2014","sql2012"
        PS C:\> $servers | Get-DbaLinkedServer | Test-DbaLinkedServerConnection

        Test all Linked Servers for the SQL Server instances sql2016, sql2014 and sql2012

    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            if ($instance.LinkedLive) {
                $linkedServerCollection = $instance.LinkedServer
            } else {
                try {
                    $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
                } catch {
                    Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
                }
                $linkedServerCollection = $server.LinkedServers
            }

            foreach ($ls in $linkedServerCollection) {
                Write-Message -Level Verbose -Message "Testing linked server $($ls.name) on server $($ls.parent.name)"
                try {
                    $null = $ls.TestConnection()
                    $result = "Success"
                    $connectivity = $true
                } catch {
                    $result = $_.Exception.InnerException.InnerException.Message
                    $connectivity = $false
                }

                New-Object Sqlcollaborative.Dbatools.Validation.LinkedServerResult($ls.parent.ComputerName, $ls.parent.ServiceName, $ls.parent.DomainInstanceName, $ls.Name, $ls.DataSource, $connectivity, $result)
            }
        }
    }
}