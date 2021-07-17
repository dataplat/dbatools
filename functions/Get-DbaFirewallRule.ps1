function Get-DbaFirewallRule {
    <#
    .SYNOPSIS
        Returns firewall rules for SQL Server instances from the target computer.

    .DESCRIPTION
        Returns firewall rules for SQL Server instances from the target computer.

        This is basically a wrapper around Get-NetFirewallRule executed at the target computer.
        So this only works if Get-NetFirewallRule works on the target computer.

        The functionality is currently limited to returning rules from a given group filtered by an optional filter scriptblock.
        Help to extend the functionality is welcome.

        As long as you can read this note here, there may be breaking changes in future versions.
        So please review your scripts using this command after updating dbatools.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

        Currently only the ComputerName part is used to connect to the target computer.
        Filtering for a specific instance has to be done with FilterScript.

    .PARAMETER Credential
        Credential object used to connect to the Computer as a different user.

    .PARAMETER Group
        Returns firewall rules from the given group.
        Defaults to 'SQL Server'.

    .PARAMETER FilterScript
        A scriptblock that is used with Where-Object at the target computer to filter the returned firewall rules.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Firewall, Network
        Author: Andreas Jordan (@JordanOrdix), ordix.de

        Website: https://dbatools.io
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaFirewallRule

    .EXAMPLE
        PS C:\> Get-DbaFirewallRule -SqlInstance SRV1

        Returns all firewall rules from SRV1 related to SQL Server.

    .EXAMPLE
        PS C:\> Get-DbaFirewallRule -SqlInstance SRV1 -Group 'SQL'

        Returns all firewall rules in group 'SQL' from SRV1.

    .EXAMPLE
        PS C:\> Get-DbaFirewallRule -SqlInstance SRV1 -FilterScript { $_.DisplayName -eq 'SQL Server default instance' }

        Returns the firewall rules with the DisplayName 'SQL Server default instance' from SRV1.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$Credential,
        [string]$Group = 'SQL Server',
        [scriptblock]$FilterScript,
        [switch]$EnableException
    )

    begin {
        $cmdScriptBlock = {
            # This scriptblock will be processed by Invoke-Command2.
            $firewallRuleParameters = $args[0]

            try {
                $successful = $true
                $cimInstance = New-NetFirewallRule @firewallRuleParameters -WarningVariable warn -ErrorVariable err -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                if ($warn.Count -gt 0) {
                    $successful = $false
                } else {
                    # Change from an empty System.Collections.ArrayList to $null for better readability
                    $warn = $null
                }
                if ($err.Count -gt 0) {
                    $successful = $false
                } else {
                    # Change from an empty System.Collections.ArrayList to $null for better readability
                    $err = $null
                }
                [PSCustomObject]@{
                    Successful  = $successful
                    CimInstance = $cimInstance
                    Warning     = $warn
                    Error       = $err
                    Exception   = $null
                }
            } catch {
                [PSCustomObject]@{
                    Successful  = $false
                    CimInstance = $null
                    Warning     = $null
                    Error       = $null
                    Exception   = $_
                }
            }
        }
    }

    process {
        if (-not $Auto -and -not $Configuration) {
            Stop-Function -Message "If -Auto is not used, you have to provide the exact configuration of the firewall rule with -Configuration."
            return
        }

        foreach ($instance in $SqlInstance) {
            $config = @{ }
            $programNeeded = $false
            $browserNeeded = $false

            if ($Auto) {
                # Apply the defaults
                $config = @{
                    Group     = 'SQL Server'
                    Enabled   = 'True'
                    Direction = 'Inbound'
                    Protocol  = 'TCP'
                }

                # Test for default or named instance
                if ($instance.InstanceName -eq 'MSSQLSERVER') {
                    $config['DisplayName'] = 'SQL Server default instance'
                } else {
                    $config['DisplayName'] = "SQL Server instance $($instance.InstanceName)"
                    $browserNeeded = $true
                }

                # Get information about IP addresses for LocalPort
                try {
                    $tcpIpAddresses = Get-DbaNetworkConfiguration -SqlInstance $instance -Credential $Credential -OutputType TcpIpAddresses -EnableException
                } catch {
                    Stop-Function -Message "Failed." -Target $instance -ErrorRecord $_ -Continue
                }

                if ($tcpIpAddresses.Count -gt 1) {
                    Stop-Function -Message "SQL Server instance $instance listens on more than one IP addresses. This is currently not supported by this command." -Continue
                }

                if ($tcpIpAddresses.TcpPort -ne '') {
                    $config['LocalPort'] = $tcpIpAddresses.TcpPort
                    if ($tcpIpAddresses.TcpPort -ne '1433') {
                        $browserNeeded = $true
                    }
                } else {
                    $programNeeded = $true
                }

                if ($programNeeded) {
                    # Get information about service for Program
                    try {
                        $service = Get-DbaService -ComputerName $instance.ComputerName -InstanceName $instance.InstanceName -Credential $Credential -Type Engine -EnableException
                    } catch {
                        Stop-Function -Message "Failed." -Target $instance -ErrorRecord $_ -Continue
                    }
                    $config['Program'] = $service.BinaryPath -replace '^"?(.*sqlservr.exe).*$', '$1'
                }
            }

            # Apply the given configuration
            if ($Configuration) {
                foreach ($param in $Configuration.Keys) {
                    $config[$param] = $Configuration[$param]
                }
            }

            # Run the command for the instance
            if ($PSCmdlet.ShouldProcess($instance, "Creating firewall rule for instance $($instance.InstanceName) on $($instance.ComputerName)")) {
                try {
                    $commandResult = Invoke-Command2 -ComputerName $instance.ComputerName -Credential $Credential -ScriptBlock $cmdScriptBlock -ArgumentList $config
                } catch {
                    Stop-Function -Message "Failed to execute command on $($instance.ComputerName) for instance $($instance.InstanceName)." -Target $instance -ErrorRecord $_ -Continue
                }

                # Output information
                [PSCustomObject]@{
                    ComputerName = $instance.ComputerName
                    InstanceName = $instance.InstanceName
                    SqlInstance  = $instance.SqlFullName.Trim('[]')
                    DisplayName  = $config['DisplayName']
                    Successful   = $commandResult.Successful
                    Status       = $commandResult.CimInstance.Status
                    Warning      = $commandResult.Warning
                    Error        = $commandResult.Error
                    Exception    = $commandResult.Exception
                    Details      = $commandResult
                } | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, DisplayName, Successful, Status, Warning, Error, Exception
            }

            # Firewall rule for the instance is in place, let's see if we need one for the SQL Server Browser
            if ($browserNeeded) {
                # Apply the defaults
                $config = @{
                    DisplayName = 'SQL Server Browser'
                    Group       = 'SQL Server'
                    Enabled     = 'True'
                    Direction   = 'Inbound'
                    Protocol    = 'UDP'
                    LocalPort   = 1434
                }

                # Apply the given configuration
                if ($Configuration) {
                    foreach ($param in $Configuration.Keys) {
                        $config[$param] = $Configuration[$param]
                    }
                }

                # Run the command for the browser
                if ($PSCmdlet.ShouldProcess($instance, "Creating firewall rule for SQL Server Browser on $($instance.ComputerName)")) {
                    try {
                        $commandResult = Invoke-Command2 -ComputerName $instance.ComputerName -Credential $Credential -ScriptBlock $cmdScriptBlock -ArgumentList $config
                    } catch {
                        Stop-Function -Message "Failed to execute command on $($instance.ComputerName) for instance $($instance.InstanceName)." -Target $instance -ErrorRecord $_ -Continue
                    }

                    # Output information
                    [PSCustomObject]@{
                        ComputerName = $instance.ComputerName
                        InstanceName = $instance.InstanceName
                        SqlInstance  = $instance.SqlFullName.Trim('[]')
                        DisplayName  = $config['DisplayName']
                        Successful   = $commandResult.Successful
                        Status       = $commandResult.CimInstance.Status
                        Warning      = $commandResult.Warning
                        Error        = $commandResult.Error
                        Exception    = $commandResult.Exception
                        Details      = $commandResult
                    } | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, DisplayName, Successful, Status, Warning, Error, Exception
                }
            }
        }
    }
}