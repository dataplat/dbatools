function New-DbaFirewallRule {
    <#
    .SYNOPSIS
        Creates Windows firewall rules for SQL Server instances to allow network connectivity

    .DESCRIPTION
        Creates inbound Windows firewall rules for SQL Server instances, Browser service, and Dedicated Admin Connection (DAC) to allow network connectivity.
        This automates the tedious post-installation task of configuring firewall access for SQL Server, eliminating the need to manually determine ports and create rules through Windows Firewall GUI or netsh commands.

        By default, the function creates program-based firewall rules that target SQL Server executables (sqlservr.exe, sqlbrowser.exe).
        This approach allows instances to work regardless of port configuration changes - named instances on different ports or default instances on non-standard ports are automatically allowed without needing to update firewall rules.
        Alternatively, you can use -RuleType Port to create traditional port-based firewall rules.

        This is a wrapper around New-NetFirewallRule executed remotely on the target computer via Invoke-Command2.
        Both DisplayName and Name are set to the same value to ensure unique rule identification and prevent duplicates.
        All rules use the "SQL Server" group for easy management with Get-DbaFirewallRule.

        The functionality is currently limited. Help to extend the functionality is welcome.

        As long as you can read this note here, there may be breaking changes in future versions.
        So please review your scripts using this command after updating dbatools.

        With -RuleType Program (default), the firewall rule for the instance itself will have the following configuration (parameters for New-NetFirewallRule):

            DisplayName = 'SQL Server default instance' or 'SQL Server instance <InstanceName>'
            Name        = 'SQL Server default instance' or 'SQL Server instance <InstanceName>'
            Group       = 'SQL Server'
            Enabled     = 'True'
            Direction   = 'Inbound'
            Protocol    = 'TCP'
            Program     = '<Path ending with MSSQL\Binn\sqlservr.exe>'

        With -RuleType Port, the firewall rule for the instance itself will have the following configuration (parameters for New-NetFirewallRule):

            DisplayName = 'SQL Server default instance' or 'SQL Server instance <InstanceName>'
            Name        = 'SQL Server default instance' or 'SQL Server instance <InstanceName>'
            Group       = 'SQL Server'
            Enabled     = 'True'
            Direction   = 'Inbound'
            Protocol    = 'TCP'
            LocalPort   = '<Port>'

        With -RuleType Program (default), the firewall rule for the SQL Server Browser will have the following configuration (parameters for New-NetFirewallRule):

            DisplayName = 'SQL Server Browser'
            Name        = 'SQL Server Browser'
            Group       = 'SQL Server'
            Enabled     = 'True'
            Direction   = 'Inbound'
            Protocol    = 'Any'
            Program     = '<Path ending with sqlbrowser.exe>'

        With -RuleType Port, the firewall rule for the SQL Server Browser will have the following configuration (parameters for New-NetFirewallRule):

            DisplayName = 'SQL Server Browser'
            Name        = 'SQL Server Browser'
            Group       = 'SQL Server'
            Enabled     = 'True'
            Direction   = 'Inbound'
            Protocol    = 'UDP'
            LocalPort   = '1434'

        The firewall rule for the dedicated admin connection (DAC) will have the following configuration (parameters for New-NetFirewallRule):

            DisplayName = 'SQL Server default instance (DAC)' or 'SQL Server instance <InstanceName> (DAC)'
            Name        = 'SQL Server default instance (DAC)' or 'SQL Server instance <InstanceName> (DAC)'
            Group       = 'SQL Server'
            Enabled     = 'True'
            Direction   = 'Inbound'
            Protocol    = 'TCP'
            LocalPort   = '<Port>' (typically 1434 for a default instance, but will be fetched from ERRORLOG)

        The firewall rule for the DAC will only be created if the DAC is configured for listening remotely.
        Use `Set-DbaSpConfigure -SqlInstance SRV1 -Name RemoteDacConnectionsEnabled -Value 1` to enable remote DAC before running this command.

        The firewall rule for database mirroring or Availability Groups will have the following configuration (parameters for New-NetFirewallRule):

            DisplayName = 'SQL Server default instance (DatabaseMirroring)' or 'SQL Server instance <InstanceName> (DatabaseMirroring)'
            Name        = 'SQL Server default instance (DatabaseMirroring)' or 'SQL Server instance <InstanceName> (DatabaseMirroring)'
            Group       = 'SQL Server'
            Enabled     = 'True'
            Direction   = 'Inbound'
            Protocol    = 'TCP'
            LocalPort   = '5022' (can be overwritten by using the parameter Configuration)

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER Credential
        Credential object used to connect to the Computer as a different user.

    .PARAMETER Type
        Specifies which firewall rule types to create for SQL Server network access.
        Use this when you need to create specific rules instead of the automatic detection behavior.
        Valid values are Engine (SQL Server instance), Browser (SQL Server Browser service), DAC (Dedicated Admin Connection) and DatabaseMirroring (database mirroring or Availability Groups). When omitted, the function automatically creates Engine rules plus Browser rules for non-default ports and DAC rules when remote DAC is enabled.

    .PARAMETER RuleType
        Specifies how firewall rules identify SQL Server traffic - either by targeting the executable program or by targeting specific TCP/UDP ports.
        Valid values are Program (targets sqlservr.exe and sqlbrowser.exe executables) and Port (targets TCP/UDP port numbers).
        Defaults to Program, which allows instances to work regardless of port configuration changes (named instances on different ports, default instances on non-standard ports).
        Use Port when you need traditional port-based rules or when Program-based rules cannot be created.
        Note: DAC and DatabaseMirroring rules are always port-based regardless of this setting.

    .PARAMETER Configuration
        Provides custom settings to override the default firewall rule configuration when calling New-NetFirewallRule.
        Use this when you need to restrict rules to specific network profiles (Domain, Private, Public) or modify other advanced firewall settings.
        Common examples include @{Profile = 'Domain'} to limit rules to domain networks only, or @{RemoteAddress = '192.168.1.0/24'} to restrict source IPs. The Name, DisplayName, and Group parameters are reserved and will be ignored if specified.

    .PARAMETER Force
        Forces recreation of firewall rules that already exist by deleting and recreating them.
        Use this when you need to update existing rules with new settings or when troubleshooting connectivity issues.
        Without this switch, the function will warn you about existing rules and skip their creation.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .NOTES
        Tags: Network, Connection, Firewall
        Author: Andreas Jordan (@JordanOrdix), ordix.de

        Website: https://dbatools.io
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaFirewallRule

    .OUTPUTS
        PSCustomObject

        Returns one object per firewall rule created, providing comprehensive details about the rule configuration and creation status.

        Default display properties (via Select-DefaultView):
        - ComputerName: The name of the computer where the firewall rule was created
        - InstanceName: The SQL Server instance name; $null for Browser rules
        - SqlInstance: The full SQL Server instance name (computer\instance); $null for Browser rules
        - DisplayName: The display name of the firewall rule (e.g., 'SQL Server default instance', 'SQL Server Browser')
        - Type: The type of firewall rule created (Engine, Browser, DAC, DatabaseMirroring)
        - Successful: Boolean indicating if the rule creation was successful
        - Status: Human-readable status message describing the outcome (e.g., 'The rule was successfully created.', 'The desired rule already exists. Use -Force to remove and recreate the rule.')
        - Protocol: The protocol type of the rule (TCP, UDP, or Any)
        - LocalPort: The TCP/UDP port number for port-based rules; $null for Program-based rules
        - Program: The executable program path for Program-based rules; $null for Port-based rules

        Additional properties available (using Select-Object *):
        - Name: The internal name of the firewall rule (same as DisplayName)
        - RuleConfig: Complete hashtable containing all New-NetFirewallRule parameters used to create the rule
        - Details: PSCustomObject containing remote command execution details with properties:
            - Successful: Boolean indicating overall success status
            - CimInstance: The CIM instance object returned by New-NetFirewallRule
            - Warning: Warning messages from rule creation (if any)
            - Error: Error messages from rule creation (if any)
            - Exception: Exception details if an error occurred (if any)

    .EXAMPLE
        PS C:\> New-DbaFirewallRule -SqlInstance SRV1, SRV1\TEST

        Automatically configures the needed firewall rules for both the default instance and the instance named TEST on SRV1.
        By default, creates program-based rules targeting the SQL Server executables, allowing the instances to work regardless of port configuration changes.

    .EXAMPLE
        PS C:\> New-DbaFirewallRule -SqlInstance SRV1, SRV1\TEST -RuleType Port

        Creates port-based firewall rules instead of the default program-based rules.
        This creates traditional TCP/UDP port rules for the instances.

    .EXAMPLE
        PS C:\> New-DbaFirewallRule -SqlInstance SRV1, SRV1\TEST -Configuration @{ Profile = 'Domain' }

        Automatically configures the needed firewall rules for both the default instance and the instance named TEST on SRV1,
        but configures the firewall rule for the domain profile only.

    .EXAMPLE
        PS C:\> New-DbaFirewallRule -SqlInstance SRV1\TEST -Type Engine -Force -Confirm:$false

        Creates or recreates the firewall rule for the instance TEST on SRV1. Does not prompt for confirmation.

    .EXAMPLE
        PS C:\> New-DbaFirewallRule -SqlInstance SQL01 -Type DatabaseMirroring

        Creates the firewall rule for database mirroring or Availability Groups on the default instance on SQL01 using the default port 5022.

    .EXAMPLE
        PS C:\> New-DbaFirewallRule -SqlInstance SQL02 -Type DatabaseMirroring -Configuration @{ LocalPort = '5023' }

        Creates the firewall rule for database mirroring or Availability Groups on the default instance on SQL02 using the custom port 5023.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$Credential,
        [ValidateSet('Engine', 'Browser', 'DAC', 'DatabaseMirroring')]
        [string[]]$Type,
        [ValidateSet('Program', 'Port')]
        [string]$RuleType = "Program",
        [hashtable]$Configuration,
        [switch]$Force,
        [switch]$EnableException
    )

    begin {
        if ($Configuration) {
            foreach ($notAllowedKey in 'Name', 'DisplayName', 'Group') {
                if ($notAllowedKey -in $Configuration.Keys) {
                    Write-Message -Level Verbose -Message "Key $notAllowedKey is not allowed in Configuration and will be removed."
                    $Configuration.Remove($notAllowedKey)
                }
            }
        }

        $cmdScriptBlock = {
            # This scriptblock will be processed by Invoke-Command2.
            $firewallRuleParameters = $args[0]
            $force = $args[1]

            try {
                if (-not (Get-Command -Name New-NetFirewallRule -ErrorAction SilentlyContinue)) {
                    throw 'The module NetSecurity with the command New-NetFirewallRule is missing on the target computer, so New-DbaFirewallRule is not supported.'
                }
                $successful = $true
                if ($force) {
                    $null = Remove-NetFirewallRule -Name $firewallRuleParameters.Name -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                }
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
        foreach ($instance in $SqlInstance) {
            $rules = @( )
            $programNeeded = $false
            $browserNeeded = $false
            if ($PSBoundParameters.Type) {
                $browserOptional = $false
            } else {
                $browserOptional = $true
            }

            # Create rule for instance
            if (-not $PSBoundParameters.Type -or 'Engine' -in $PSBoundParameters.Type) {
                # Apply the defaults
                $rule = @{
                    Type         = 'Engine'
                    InstanceName = $instance.InstanceName
                    Config       = @{
                        Group     = 'SQL Server'
                        Enabled   = 'True'
                        Direction = 'Inbound'
                        Protocol  = 'TCP'
                    }
                }

                # Test for default or named instance
                if ($instance.InstanceName -eq 'MSSQLSERVER') {
                    $rule.Config.DisplayName = 'SQL Server default instance'
                    $rule.Config.Name = 'SQL Server default instance'
                    $rule.SqlInstance = $instance.ComputerName
                } else {
                    $rule.Config.DisplayName = "SQL Server instance $($instance.InstanceName)"
                    $rule.Config.Name = "SQL Server instance $($instance.InstanceName)"
                    $rule.SqlInstance = $instance.ComputerName + '\' + $instance.InstanceName
                    $browserNeeded = $true
                }

                # Get information about IP addresses for LocalPort
                try {
                    $tcpIpAddresses = Get-DbaNetworkConfiguration -SqlInstance $instance -Credential $Credential -OutputType TcpIpAddresses -EnableException
                } catch {
                    Stop-Function -Message "Failed." -Target $instance -ErrorRecord $_ -Continue
                }

                if ($tcpIpAddresses.Count -gt 1) {
                    # I would have to test this, so I better not support this in the first version.
                    # As LocalPort is [<String[]>], $tcpIpAddresses.TcpPort will probably just work with the current implementation.
                    Stop-Function -Message "SQL Server instance $instance listens on more than one IP addresses. This is currently not supported by this command." -Continue
                }

                # Determine whether to use Program or Port based on RuleType parameter
                if ($RuleType -eq 'Program') {
                    # Try to get the program path for executable-based rule
                    try {
                        $service = Get-DbaService -ComputerName $instance.ComputerName -InstanceName $instance.InstanceName -Credential $Credential -Type Engine -EnableException
                        $programPath = $service.BinaryPath -replace '^"?(.*sqlservr.exe).*$', '$1'
                        if ($programPath) {
                            $rule.Config.Program = $programPath
                            Write-Message -Level Verbose -Message "Creating program-based firewall rule targeting: $programPath"
                        } else {
                            Write-Message -Level Warning -Message "Could not determine executable path for instance $instance. Falling back to port-based rule."
                            $programNeeded = $false
                        }
                    } catch {
                        Write-Message -Level Warning -Message "Failed to get service information for instance $instance. Falling back to port-based rule."
                        $programNeeded = $false
                    }

                    # If we couldn't get the program path, fall back to port-based rule
                    if (-not $rule.Config.Program) {
                        if ($tcpIpAddresses.TcpPort -ne '') {
                            $rule.Config.LocalPort = $tcpIpAddresses.TcpPort
                            Write-Message -Level Verbose -Message "Fallback: Creating port-based firewall rule on port: $($tcpIpAddresses.TcpPort)"
                        } else {
                            Stop-Function -Message "Cannot create firewall rule for instance $instance. No port configured and executable path unavailable." -Continue
                        }
                    }
                } else {
                    # RuleType is 'Port' - use port-based rule
                    if ($tcpIpAddresses.TcpPort -ne '') {
                        $rule.Config.LocalPort = $tcpIpAddresses.TcpPort
                        Write-Message -Level Verbose -Message "Creating port-based firewall rule on port: $($tcpIpAddresses.TcpPort)"
                    } else {
                        Stop-Function -Message "Cannot create port-based firewall rule for instance $instance. Instance is configured for dynamic ports. Use -RuleType Program instead." -Continue
                    }
                }

                # Determine if Browser rule is needed (for named instances or non-default ports)
                if ($tcpIpAddresses.TcpPort -ne '' -and $tcpIpAddresses.TcpPort -ne '1433') {
                    $browserNeeded = $true
                }

                $rules += $rule
            }

            # Create rule for Browser
            if ((-not $PSBoundParameters.Type -and $browserNeeded) -or 'Browser' -in $PSBoundParameters.Type) {
                # Apply the defaults
                $rule = @{
                    Type         = 'Browser'
                    InstanceName = $null
                    SqlInstance  = $null
                    Config       = @{
                        DisplayName = 'SQL Server Browser'
                        Name        = 'SQL Server Browser'
                        Group       = 'SQL Server'
                        Enabled     = 'True'
                        Direction   = 'Inbound'
                        Protocol    = 'UDP'
                    }
                }

                # Determine whether to use Program or Port based on RuleType parameter
                if ($RuleType -eq 'Program') {
                    # Try to get the SQL Browser service executable path
                    try {
                        $browserService = Get-DbaService -ComputerName $instance.ComputerName -Credential $Credential -Type Browser -EnableException | Select-Object -First 1
                        $browserPath = $browserService.BinaryPath -replace '^"?(.*sqlbrowser.exe).*$', '$1'
                        if ($browserPath) {
                            $rule.Config.Program = $browserPath
                            $rule.Config.Protocol = 'Any'
                            Write-Message -Level Verbose -Message "Creating program-based firewall rule for Browser targeting: $browserPath"
                        } else {
                            Write-Message -Level Warning -Message "Could not determine SQL Browser executable path. Falling back to port-based rule."
                            $rule.Config.LocalPort = '1434'
                        }
                    } catch {
                        Write-Message -Level Warning -Message "Failed to get SQL Browser service information. Falling back to port-based rule."
                        $rule.Config.LocalPort = '1434'
                    }
                } else {
                    # RuleType is 'Port' - use port-based rule
                    $rule.Config.LocalPort = '1434'
                    Write-Message -Level Verbose -Message "Creating port-based firewall rule for Browser on UDP port: 1434"
                }

                $rules += $rule
            }

            # Create rule for the dedicated admin connection (DAC)
            if (-not $PSBoundParameters.Type -or 'DAC' -in $PSBoundParameters.Type) {
                # As we create firewall rules, we probably don't have access to the instance yet. So we have to get the port of the DAC via Invoke-Command2.
                # Get-DbaStartupParameter also uses Invoke-Command2 to get the location of ERRORLOG.
                # We only scan the current log because this command is typically run shortly after the installation and should include the needed information.
                try {
                    $errorLogPath = Get-DbaStartupParameter -SqlInstance $instance -Credential $Credential -Simple -EnableException | Select-Object -ExpandProperty ErrorLog
                    $dacMessage = Invoke-Command2 -Raw -ComputerName $instance.ComputerName -ArgumentList $errorLogPath -ScriptBlock {
                        Get-Content -Path $args[0] |
                            Select-String -Pattern 'Dedicated admin connection support was established for listening.+' |
                            Select-Object -Last 1 |
                            ForEach-Object { $_.Matches.Value }
                    }
                    Write-Message -Level Debug -Message "Last DAC message in ERRORLOG: '$dacMessage'"
                } catch {
                    Stop-Function -Message "Failed to execute command to get information for DAC on $($instance.ComputerName) for instance $($instance.InstanceName)." -Target $instance -ErrorRecord $_ -Continue
                }

                if (-not $dacMessage) {
                    Write-Message -Level Warning -Message "No information about the dedicated admin connection (DAC) found in ERRORLOG, cannot create firewall rule for DAC. Use 'Set-DbaSpConfigure -SqlInstance '$instance' -Name RemoteDacConnectionsEnabled -Value 1' to enable remote DAC and try again."
                } elseif ($dacMessage -match 'locally') {
                    Write-Message -Level Verbose -Message "Dedicated admin connection is only listening locally, so no firewall rule is needed."
                } else {
                    $dacPort = $dacMessage -replace '^.* (\d+).$', '$1'
                    Write-Message -Level Verbose -Message "Dedicated admin connection is listening remotely on port $dacPort."

                    # Apply the defaults
                    $rule = @{
                        Type         = 'DAC'
                        InstanceName = $instance.InstanceName
                        Config       = @{
                            Group     = 'SQL Server'
                            Enabled   = 'True'
                            Direction = 'Inbound'
                            Protocol  = 'TCP'
                            LocalPort = $dacPort
                        }
                    }

                    # Test for default or named instance
                    if ($instance.InstanceName -eq 'MSSQLSERVER') {
                        $rule.Config.DisplayName = 'SQL Server default instance (DAC)'
                        $rule.Config.Name = 'SQL Server default instance (DAC)'
                        $rule.SqlInstance = $instance.ComputerName
                    } else {
                        $rule.Config.DisplayName = "SQL Server instance $($instance.InstanceName) (DAC)"
                        $rule.Config.Name = "SQL Server instance $($instance.InstanceName) (DAC)"
                        $rule.SqlInstance = $instance.ComputerName + '\' + $instance.InstanceName
                    }

                    $rules += $rule
                }
            }

            # Create rule for database mirroring or Availability Groups
            if ('DatabaseMirroring' -in $PSBoundParameters.Type) {
                # Apply the defaults
                $rule = @{
                    Type         = 'DatabaseMirroring'
                    InstanceName = $instance.InstanceName
                    Config       = @{
                        Group     = 'SQL Server'
                        Enabled   = 'True'
                        Direction = 'Inbound'
                        Protocol  = 'TCP'
                        LocalPort = '5022'
                    }
                }

                # Test for default or named instance
                if ($instance.InstanceName -eq 'MSSQLSERVER') {
                    $rule.Config.DisplayName = 'SQL Server default instance (DatabaseMirroring)'
                    $rule.Config.Name = 'SQL Server default instance (DatabaseMirroring)'
                    $rule.SqlInstance = $instance.ComputerName
                } else {
                    $rule.Config.DisplayName = "SQL Server instance $($instance.InstanceName) (DatabaseMirroring)"
                    $rule.Config.Name = "SQL Server instance $($instance.InstanceName) (DatabaseMirroring)"
                    $rule.SqlInstance = $instance.ComputerName + '\' + $instance.InstanceName
                }

                $rules += $rule
            }

            foreach ($rule in $rules) {
                # Apply the given configuration
                if ($Configuration) {
                    foreach ($param in $Configuration.Keys) {
                        $rule.Config.$param = $Configuration.$param
                    }
                }

                # Run the command for the instance
                if ($PSCmdlet.ShouldProcess($instance, "Creating firewall rule for instance $($instance.InstanceName) on $($instance.ComputerName)")) {
                    try {
                        $commandResult = Invoke-Command2 -ComputerName $instance.ComputerName -Credential $Credential -ScriptBlock $cmdScriptBlock -ArgumentList $rule.Config, $Force
                    } catch {
                        Stop-Function -Message "Failed to execute command on $($instance.ComputerName) for instance $($instance.InstanceName)." -Target $instance -ErrorRecord $_ -Continue
                    }

                    if ($commandResult.Error.Count -eq 1 -and $commandResult.Error[0] -match 'Cannot create a file when that file already exists') {
                        $status = 'The desired rule already exists. Use -Force to remove and recreate the rule.'
                        $commandResult.Error = $null
                        if ($rule.Type -eq 'Browser' -and $browserOptional) {
                            $commandResult.Successful = $true
                        }
                    } elseif ($commandResult.CimInstance.Status -match 'The rule was parsed successfully from the store') {
                        $status = 'The rule was successfully created.'
                    } else {
                        $status = $commandResult.CimInstance.Status
                    }

                    if ($commandResult.Warning) {
                        Write-Message -Level Verbose -Message "commandResult.Warning: $($commandResult.Warning)."
                        $status += " Warning: $($commandResult.Warning)."
                    }
                    if ($commandResult.Error) {
                        Write-Message -Level Verbose -Message "commandResult.Error: $($commandResult.Error)."
                        $status += " Error: $($commandResult.Error)."
                    }
                    if ($commandResult.Exception) {
                        Write-Message -Level Verbose -Message "commandResult.Exception: $($commandResult.Exception)."
                        $status += " Exception: $($commandResult.Exception)."
                    }

                    # Output information
                    [PSCustomObject]@{
                        ComputerName = $instance.ComputerName
                        InstanceName = $rule.InstanceName
                        SqlInstance  = $rule.SqlInstance
                        DisplayName  = $rule.Config.DisplayName
                        Name         = $rule.Config.Name
                        Type         = $rule.Type
                        Protocol     = $rule.Config.Protocol
                        LocalPort    = $rule.Config.LocalPort
                        Program      = $rule.Config.Program
                        RuleConfig   = $rule.Config
                        Successful   = $commandResult.Successful
                        Status       = $status
                        Details      = $commandResult
                    } | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, DisplayName, Type, Successful, Status, Protocol, LocalPort, Program
                }
            }
        }
    }
}