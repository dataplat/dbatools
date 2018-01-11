function Test-DbaLinkedServerConnection {
    <#
        .SYNOPSIS
            Test all linked servers from the sql servers passed

        .DESCRIPTION
            Test each linked server on the instance

        .PARAMETER SqlInstance
            The SQL Server that you're connecting to.

        .PARAMETER SqlCredential
            Credential object used to connect to the SQL Server as a different user

        .PARAMETER EnableException
                By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.

                This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
                Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: LinkedServer
            Author: Thomas LaRock ( https://thomaslarock.com )

            dbatools PowerShell module (https://dbatools.io)
            Copyright (C) 2017 Chrissy LeMaire
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Test-DbaLinkedServerConnection

        .EXAMPLE
            Test-DbaLinkedServerConnection -SqlInstance DEV01

            Test all Linked Servers for the SQL Server instance DEV01

        .EXAMPLE
            Test-DbaLinkedServerConnection -SqlInstance sql2016 | Out-File C:\temp\results.txt

            Test all Linked Servers for the SQL Server instance sql2016 and output results to file

        .EXAMPLE
            Test-DbaLinkedServerConnection -SqlInstance sql2016, sql2014, sql2012

            Test all Linked Servers for the SQL Server instances sql2016, sql2014 and sql2012

        .EXAMPLE
            $servers = "sql2016","sql2014","sql2012"
            $servers | Test-DbaLinkedServerConnection -SqlCredential (Get-Credential sqladmin)

            Test all Linked Servers for the SQL Server instances sql2016, sql2014 and sql2012 using SQL login credentials

        .EXAMPLE
            $servers | Get-DbaLinkedServer | Test-DbaLinkedServerConnection

            Test all Linked Servers for the SQL Server instances sql2016, sql2014 and sql2012
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch][Alias('Silent')]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            if ($instance.LinkedLive) {
                $linkedServerCollection = $instance.LinkedServer
            }
            else {
                try {
                    Write-Message -Level Verbose -Message "Connecting to $instance"
                    $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
                }
                catch {
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
                }
            }

            $linkedServerCollection = $server.LinkedServers

            foreach ($ls in $linkedServerCollection) {
                Write-Message -Level Verbose -Message "Testing linked server $($ls.name) on server $($ls.parent.name)"
                try {
                    $null = $ls.TestConnection()
                    $result = "Success"
                    $connectivity = $true
                }
                catch {
                    $result = $_.Exception.InnerException.InnerException.Message
                    $connectivity = $false
                }

                New-Object Sqlcollaborative.Dbatools.Validation.LinkedServerResult($ls.parent.NetName, $ls.parent.ServiceName, $ls.parent.DomainInstanceName, $ls.Name, $ls.DataSource, $connectivity, $result)
            }
        }
    }
}
