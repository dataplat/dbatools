function Invoke-DbaDbccDropCleanBuffer {
    <#
    .SYNOPSIS
        Execution of Database Console Command DBCC DROPCLEANBUFFERS

    .DESCRIPTION
        Allows execution of Database Console Command DBCC DROPCLEANBUFFERS

        Removes all clean buffers from the buffer pool, and columnstore objects from the columnstore object pool.

        Read more:
            - https://docs.microsoft.com/en-us/sql/t-sql/database-console-commands/dbcc-dropcleanbuffers-transact-sql

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER NoInformationalMessages
        Suppresses all informational messages.

    .PARAMETER WhatIf
        Shows what would happen if the cmdlet runs. The cmdlet is not run.

    .PARAMETER Confirm
        Prompts you for confirmation before running the cmdlet.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: DBCC
        Author: Patrick Flynn (@sqllensman)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbaDbccDropCleanBuffer

    .EXAMPLE
        PS C:\> Invoke-DbaDbccDropCleanBuffer -SqlInstance SqlServer2017

        Runs the command DBCC DROPCLEANBUFFERS against the instance SqlServer2017 using Windows Authentication

    .EXAMPLE
        PS C:\> Invoke-DbaDbccDropCleanBuffer -SqlInstance SqlServer2017 -NoInformationalMessages

        Runs the command DBCC DROPCLEANBUFFERS WITH NO_INFOMSGS against the instance SqlServer2017 using Windows Authentication

    .EXAMPLE
        PS C:\> 'Sql1','Sql2/sqlexpress' | Invoke-DbaDbccDropCleanBuffer -WhatIf

        Displays what will happen if command DBCC DROPCLEANBUFFERS is called against Sql1 and Sql2/sqlexpress

    .EXAMPLE
        PS C:\> $cred = Get-Credential sqladmin
        PS C:\> Invoke-DbaDbccDropCleanBuffer -SqlInstance Server1 -SqlCredential $cred

        Connects using sqladmin credential and executes command DBCC DROPCLEANBUFFERS for instance Server1

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$NoInformationalMessages,
        [switch]$EnableException
    )
    begin {

        $stringBuilder = New-Object System.Text.StringBuilder
        $null = $stringBuilder.Append("DBCC DROPCLEANBUFFERS")
        if (Test-Bound -ParameterName NoInformationalMessages) {
            $null = $stringBuilder.Append(" WITH NO_INFOMSGS")
        }
    }
    process {
        $query = $StringBuilder.ToString()

        foreach ($instance in $SqlInstance) {
            Write-Message -Message "Attempting Connection to $instance" -Level Verbose
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            try {
                if ($Pscmdlet.ShouldProcess($server.Name, "Execute the command $query against $instance")) {
                    Write-Message -Message "Query to run: $query" -Level Verbose
                    $results = $server | Invoke-DbaQuery  -Query $query -MessagesToOutput
                }
            } catch {
                Stop-Function -Message "Failure running DBCC DROPCLEANBUFFERS" -ErrorRecord $_ -Target $server -Continue
            }
            If ($Pscmdlet.ShouldProcess("console", "Outputting object")) {
                [PSCustomObject]@{
                    ComputerName = $server.ComputerName
                    InstanceName = $server.ServiceName
                    SqlInstance  = $server.DomainInstanceName
                    Cmd          = $query.ToString()
                    Output       = $results
                }
            }
        }
    }
}