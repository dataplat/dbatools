function Stop-DbaProcess {
    <#
    .SYNOPSIS
        This command finds and kills SQL Server processes.

    .DESCRIPTION
        This command kills all spids associated with a spid, login, host, program or database.

        If you are attempting to kill your own login sessions, the process performing the kills will be skipped.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Spid
        Specifies one or more spids to be killed. Options for this parameter are auto-populated from the server.

    .PARAMETER Login
        Specifies one or more login names whose processes will be killed. Options for this parameter are auto-populated from the server and only login names that have active processes are offered.

    .PARAMETER Hostname
        Specifies one or more client hostnames whose processes will be killed. Options for this parameter are auto-populated from the server and only hostnames that have active processes are offered.

    .PARAMETER Program
        Specifies one or more client programs whose processes will be killed. Options for this parameter are auto-populated from the server and only programs that have active processes are offered.

    .PARAMETER Database
        Specifies one or more databases whose processes will be killed. Options for this parameter are auto-populated from the server and only databases that have active processes are offered.

        This parameter is auto-populated from -SqlInstance and allows only database names that have active processes. You can specify one or more Databases whose processes will be killed.

    .PARAMETER ExcludeSpid
        Specifies one or more spids which will not be killed. Options for this parameter are auto-populated from the server.

        Exclude is the last filter to run, so even if a spid matches (for example) Hosts, if it's listed in Exclude it wil be excluded.

    .PARAMETER InputObject
        This is the process object passed by Get-DbaProcess if using a pipeline.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Processes
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Stop-DbaProcess

    .EXAMPLE
        PS C:\> Stop-DbaProcess -SqlInstance sqlserver2014a -Login base\ctrlb, sa

        Finds all processes for base\ctrlb and sa on sqlserver2014a, then kills them. Uses Windows Authentication to login to sqlserver2014a.

    .EXAMPLE
        PS C:\> Stop-DbaProcess -SqlInstance sqlserver2014a -SqlCredential $credential -Spid 56, 77

        Finds processes for spid 56 and 57, then kills them. Uses alternative (SQL or Windows) credentials to login to sqlserver2014a.

    .EXAMPLE
        PS C:\> Stop-DbaProcess -SqlInstance sqlserver2014a -Program 'Microsoft SQL Server Management Studio'

        Finds processes that were created in Microsoft SQL Server Management Studio, then kills them.

    .EXAMPLE
        PS C:\> Stop-DbaProcess -SqlInstance sqlserver2014a -Hostname workstationx, server100

        Finds processes that were initiated (computers/clients) workstationx and server 1000, then kills them.

    .EXAMPLE
        PS C:\> Stop-DbaProcess -SqlInstance sqlserver2014  -Database tempdb -WhatIf

        Shows what would happen if the command were executed.

    .EXAMPLE
        PS C:\> Get-DbaProcess -SqlInstance sql2016 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess

        Finds processes that were created with dbatools, then kills them.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess)]
    param (
        [parameter(Mandatory, ParameterSetName = "Server")]
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [int[]]$Spid,
        [int[]]$ExcludeSpid,
        [string[]]$Database,
        [string[]]$Login,
        [string[]]$Hostname,
        [string[]]$Program,
        [parameter(ValueFromPipeline, Mandatory, ParameterSetName = "Process")]
        [object[]]$InputObject,
        [switch]$EnableException
    )

    process {
        if (Test-FunctionInterrupt) { return }

        if (-not $InputObject) {
            $bound = $PSBoundParameters
            $null = $bound.Remove("WhatIf")
            $null = $bound.Remove("Confirm")
            $InputObject = Get-DbaProcess @bound
        }

        foreach ($session in $InputObject) {
            $sourceserver = $session.Parent

            if (!$sourceserver) {
                Stop-Function -Message "Only process objects can be passed through the pipeline." -Category InvalidData -Target $session
                return
            }

            $currentspid = $session.spid

            if ($sourceserver.ConnectionContext.ProcessID -eq $currentspid) {
                Write-Message -Level Warning -Message "Skipping spid $currentspid because you cannot use KILL to kill your own process." -Target $session
                Continue
            }

            if ($Pscmdlet.ShouldProcess($sourceserver, "Killing spid $currentspid")) {
                try {
                    $sourceserver.KillProcess($currentspid)
                    [pscustomobject]@{
                        SqlInstance = $sourceserver.name
                        Spid        = $session.Spid
                        Login       = $session.Login
                        Host        = $session.Host
                        Database    = $session.Database
                        Program     = $session.Program
                        Status      = 'Killed'
                    }
                } catch {
                    Stop-Function -Message "Couldn't kill spid $currentspid." -Target $session -ErrorRecord $_ -Continue
                }
            }
        }
    }
}