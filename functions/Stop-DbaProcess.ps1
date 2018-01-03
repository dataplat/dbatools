function Stop-DbaProcess {
    <#
        .SYNOPSIS
            This command finds and kills SQL Server processes.

        .DESCRIPTION
            This command kills all spids associated with a spid, login, host, program or database.

            If you are attempting to kill your own login sessions, the process performing the kills will be skipped.

        .PARAMETER SqlInstance
            The SQL Server instance.

        .PARAMETER SqlCredential
            Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

            $scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.

            Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

            To connect as a different Windows user, run PowerShell as that user.

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

        .PARAMETER ProcessCollection
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
            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Stop-DbaProcess

        .EXAMPLE
            Stop-DbaProcess -SqlInstance sqlserver2014a -Login base\ctrlb, sa

            Finds all processes for base\ctrlb and sa on sqlserver2014a, then kills them. Uses Windows Authentication to login to sqlserver2014a.

        .EXAMPLE
            Stop-DbaProcess -SqlInstance sqlserver2014a -SqlCredential $credential -Spids 56, 77

            Finds processes for spid 56 and 57, then kills them. Uses alternative (SQL or Windows) credentials to login to sqlserver2014a.

        .EXAMPLE
            Stop-DbaProcess -SqlInstance sqlserver2014a -Programs 'Microsoft SQL Server Management Studio'

            Finds processes that were created in Microsoft SQL Server Management Studio, then kills them.

        .EXAMPLE
            Stop-DbaProcess -SqlInstance sqlserver2014a -Hosts workstationx, server100

            Finds processes that were initiated by hosts (computers/clients) workstationx and server 1000, then kills them.

        .EXAMPLE
            Stop-DbaProcess -SqlInstance sqlserver2014  -Database tempdb -WhatIf

            Shows what would happen if the command were executed.

        .EXAMPLE
            Get-DbaProcess -SqlInstance sql2016 -Programs 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess

            Finds processes that were created with dbatools, then kills them.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess)]
    Param (
        [parameter(Mandatory, ParameterSetName = "Server")]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter]$SqlInstance,
        [Alias("Credential")]
        [PSCredential]$SqlCredential,
        [int[]]$Spid,
        [int[]]$ExcludeSpid,
        [string[]]$Database,
        [string[]]$Login,
        [string[]]$Hostname,
        [string[]]$Program,
        [parameter(ValueFromPipeline = $true, Mandatory = $true, ParameterSetName = "Process")]
        [object[]]$ProcessCollection,
        [switch][Alias('Silent')]$EnableException
    )

    process {
        if (Test-FunctionInterrupt) { return }

        if (!$ProcessCollection) {
            $ProcessCollection = Get-DbaProcess @PSBoundParameters
        }

        foreach ($session in $ProcessCollection) {
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
                }
                catch {
                    Stop-Function -Message "Couldn't kill spid $currentspid." -Target $session -ErrorRecord $_ -Continue
                }
            }
        }
    }
}