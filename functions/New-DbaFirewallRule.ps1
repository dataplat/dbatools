function New-DbaFirewallRule {
    <#
        .SYNOPSIS
            Adds new firewall rules to Windows Firewall with Advanced Security for SQL Server components.

        .DESCRIPTION
            Based on https://ryanmangansitblog.com/2013/05/01/powershell-script-for-sql-firewall-rules/
            Adds new firewall rules to Windows Firewall with Advanced Security application for SQL Server components.
            Includes the Database Engine, SSAS, SSIS, SSRS, and more, and assigns them to a "SQL" Display Group by default.
            Unless the user provides specific ports for specific components, the default ports will be used.
            3rd party Firewalls are not supported.

        .PARAMETER ComputerName
            The target SQL Server. Default is localhost ($env:COMPUTERNAME).

        .PARAMETER Credential
            Allows you to login to $ComputerName using alternative credentials.

        .PARAMETER NetworkProfile
            Specifies the Windows Firewall Network Profile. Default is Domain.

        .PARAMETER DisplayGroup
            Specifies the Windows Firewall Display Group. Default is SQL.

        .PARAMETER PortDbEngine
            Specifies the TCP port used by the Database Engine. Default is 1433.

        .PARAMETER PortDbEngineDAC
            Specifies the TCP port used by the Database Engine Dedicated Admin Connection. Default is 1434.

        .PARAMETER PortBrowserService
            Specifies the UDP port used by the Browser Service. Default is 1434.

        .PARAMETER PortServiceBroker
            Specifies the TCP port used by the Service Broker. Default is 4022.
            Run the below TSQL query to confirm Service Broker is in use and the running port.
            SELECT name, protocol_desc, port, state_desc FROM sys.tcp_endpoints WHERE type_desc = 'SERVICE_BROKER'

        .PARAMETER PortDebuggerRPC
            Specifies the TCP port used by the TSQL Debugger/Remote Procedure Call. Default is 135.
            Please see the below documentation for additional considerations not covered by this command:
            https://docs.microsoft.com/en-us/sql/sql-server/install/configure-the-windows-firewall-to-allow-sql-server-access#BKMK_port_135
            https://docs.microsoft.com/en-us/sql/sql-server/install/configure-the-windows-firewall-to-allow-sql-server-access#BKMK_IPsec

        .PARAMETER PortSSASDefaultInstance
            Specifies the TCP port used by the SQL Server Analysis Services (SSAS) default instance. Default is 2383.

        .PARAMETER PortSSASNamedInstance
            Specifies the TCP port used by a SQL Server Analysis Services (SSAS) named instance. Default is 2382.
            NOTE: This is also needed for for "Power Pivot" named instance for SharePoint.
            Named instances use dynamic port assignments.
            As the discovery service for Analysis Services, SQL Server Browser service listens on TCP port 2382 and redirects the connection request to the port currently used by Analysis Services.

        .PARAMETER PortSSIS
            Specifies the TCP port used by SQL Server Integration Services (SSIS). Default is 135, and this port cannot be changed. Hidden parameter.
            The path to your SSIS server's MsDtsSrvr.exe will be detected, and a separate firewall rule for this specific executable is also added (CURRENTLY BROKEN FOR MULTIPLE SSIS INSTANCES).

        .PARAMETER PortSSRS
            Specifies the TCP port used by SQL Server Reporting Services (SSRS). Default is 80.

        .PARAMETER PortSSRSSSL
            Specifies the TCP port used by SQL Server Reporting Services (SSRS) using SSL. Default is 443.

        .PARAMETER PortSSMSBrowse
            Specifies the UDP port used by the SQL Server Management Studio (SSMS) Browse button. Default is 1433.

        .PARAMETER Force
            The force parameter will ignore some errors in the parameters and assume defaults.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .PARAMETER WhatIf
            If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

        .PARAMETER Confirm
            If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

        .NOTES
            Tags: Firewall, Shoe
            Author: John G Hohengarten (@wsuhoey)
            Contributors: Constantine Kokkinos (@ck), Jason Squires (@js_0505), Patrick Flynn (@sqllensman)
            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

            ###  References ###
            # https://docs.microsoft.com/en-us/sql/sql-server/install/configure-the-windows-firewall-to-allow-sql-server-access
            # https://docs.microsoft.com/en-us/sql/analysis-services/instances/configure-the-windows-firewall-to-allow-analysis-services-access
            # https://docs.microsoft.com/en-us/sql/integration-services/service/integration-services-service-ssis-service#configure-the-firewall
            # https://docs.microsoft.com/en-us/sql/reporting-services/report-server/configure-a-firewall-for-report-server-access
            # https://technet.microsoft.com/en-us/library/jj554908(v=wps.630).aspx
            # https://serverfault.com/questions/325544/how-to-create-a-windows-2008-advanced-firewall-rules-group-definition-through-th/789187#789187 # helped with setting DisplayGroup for firewall rule
            # https://sid-500.com/2017/12/11/configuring-windows-firewall-with-powershell/
            ### /References ###

        .LINK
            https://dbatools.io/New-DbaFirewallRule

        .EXAMPLE
            New-DbaFirewallRule

            Adds default ports and rules for SQL Server components, including the Database Engine, SSAS, SSIS, SSRS, to the localhost (the default since unspecified).

        .EXAMPLE
            New-DbaFirewallRule -ComputerName sql01

            Adds default ports and rules for SQL Server components, including the Database Engine, SSAS, SSIS, SSRS, to server sql01.

        .EXAMPLE
            New-DbaFirewallRule -ComputerName sql01 -PortDbEngine 5554

            Adds default ports and rules for SQL server components, including the SSAS, SSIS, SSRS, except for the Database Engine which uses port 5554, to server sql01.

        .EXAMPLE
            New-DbaFirewallRule -ComputerName sql01 -DisplayGroup "SQL Rules"

            Adds default ports and rules for SQL Server components, including the Database Engine, SSAS, SSIS, SSRS, to server sql01, and assigns them to a "SQL Rules" Display Group.

    #>
    [CmdletBinding(DefaultParameterSetName = "FirewallRules", SupportsShouldProcess = $true)]
    param (
        [Parameter(Position = 1, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer", "SqlInstance")]
        [string]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        #$Credential = [System.Management.Automation.PSCredential]::Empty, # not sure which, seen in internal/functions/Test-PSRemoting.ps1
        [securestring]$Password,

        [string]$NetworkProfile = "Domain",
        [string]$DisplayGroup = "SQL", # From New-NetFirewallRule Help: The DisplayGroup parameter cannot be specified upon object creation using the New-NetFirewallRule cmdlet, but can be modified using dot-notation and the Set-NetFirewallRule cmdlet.

        [int]$PortDbEngine = 1433,
        [int]$PortDbEngineDAC = 1434,
        [int]$PortBrowserService = 1434,
        [int]$PortServiceBroker = 4022,
        [int]$PortDebuggerRPC = 135,
        [int]$PortSSASDefaultInstance = 2383,
        [int]$PortSSASNamedInstance = 2382, # also needed for "Power Pivot" named instance for SharePoint
            # Named instances use dynamic port assignments.
            # As the discovery service for Analysis Services, SQL Server Browser service listens
            # on TCP port 2382 and redirects the connection request to the port currently used by Analysis Services. 
        [Parameter(DontShow = $true)][int] $PortSSIS = 135, # "The Integration Services service uses port 135, and the port cannot be changed"
        [int]$PortSSRS = 80,
        [int]$PortSSRSSSL = 443,
        [int]$PortSSMSBrowse = 1433,

        [switch]$Force,
        [Alias('Silent')][switch]$EnableException

    )
    
    begin {
        if (([Environment]::OSVersion).Version.Major -lt 6) {
            Write-Error "This New-DbaFirewallRule command only supports Windows 8 / Windows Server 2012 or higher, due to a dependency on NetSecurity module."
            Break
        }
    } # end begin

    process {
    Import-Module NetSecurity

    # KNOWN ISSUE: currently does not handle multiple SSIS instances, as it will try to pass an array to New-NetFirewallRule which expects a string for -Program
    $ssispath = (Get-DbaSqlService -ComputerName $ComputerName -Type SSIS).BinaryPath # provided by @sqllensman.
        
        # $ssispath # debug
        # $ssispath.GetType() # debug

    $FirewallRules =
    @{
        'DatabaseEngine' =
            @{
                'DisplayName' = "SQL Server Database Engine (TCP-in)";
                'Direction' = 'Inbound';
                'Protocol' = 'TCP';
                'LocalPort' = $portDbEngine
                'Action' = 'Allow'
                'Profile' = $networkProfile
                'Enabled' = 'True';
            };

        'DAC' =
            @{
                'DisplayName' = "SQL Dedicated Admin Connection (DAC) (TCP-in)";
                'Direction' = 'Inbound';
                'Protocol' = 'TCP';
                'LocalPort' = $portDbEngineDAC
                'Action' = 'Allow'
                'Profile' = $networkProfile
                'Enabled' = 'True'; 
            };

        'BrowserService' = # aka 'BrowserServiceUDP'
            @{
                'DisplayName' = "SQL Browser Service (UDP-in)";
                'Direction' = 'Inbound';
                'Protocol' = 'UDP';
                'LocalPort' = $portBrowserService
                'Action' = 'Allow'
                'Profile' = $networkProfile
                'Enabled' = 'True'; 
            };

        'ServiceBroker' =
            @{
                'DisplayName' = "SQL Service Broker (TCP-in)";
                'Direction' = 'Inbound';
                'Protocol' = 'TCP';
                'LocalPort' = $portServiceBroker
                'Action' = 'Allow'
                'Profile' = $networkProfile
                'Enabled' = 'True'; 
            };

        'Debugger/RPC' =
            @{
                'DisplayName' = "SQL Debugger/RPC (TCP-in)";
                'Direction' = 'Inbound';
                'Protocol' = 'TCP';
                'LocalPort' = $portDebuggerRPC
                'Action' = 'Allow'
                'Profile' = $networkProfile
                'Enabled' = 'True'; 
            };

        'SSAS' =
            @{
                'DisplayName' = "SQL Analysis Services (TCP-in)";
                'Direction' = 'Inbound';
                'Protocol' = 'TCP';
                'LocalPort' = $portSSASDefaultInstance
                'Action' = 'Allow'
                'Profile' = $networkProfile
                'Enabled' = 'True'; 
            };

        'SSASNamedInstance' = # aka 'BrowserServiceTCP' # also needed for "Power Pivot" named instance for SharePoint and any other named SSAS instances
            @{
                'DisplayName' = "SQL Browser Service (TCP-in)";
                'Direction' = 'Inbound';
                'Protocol' = 'TCP';
                'LocalPort' = $portSSASNamedInstance
                'Action' = 'Allow'
                'Profile' = $networkProfile
                'Enabled' = 'True'; 
            };

        'SSIS' =
            @{
                'DisplayName' = "SQL Integration Services (TCP-in)"; # technically a dupe of SQL Debugger/RPC (TCP-in)
                'Direction' = 'Inbound';
                'Protocol' = 'TCP';
                'LocalPort' = $portSSIS
                'Action' = 'Allow'
                'Profile' = $networkProfile
                'Enabled' = 'True'; 
            };
    <#
        # KNOWN ISSUE: currently does not handle multiple SSIS instances, as it will try to pass an array to New-NetFirewallRule which expects a string for -Program
        'SSISExe' = # this might need its own function since Program, LocalAddress, and RemoteAddress parameters don't exist in any other firewall rules
            @{
                'DisplayName' = "SQL Integration Services MsDtsSrvr.exe (TCP-in)";
                'Program' = $ssispath;
                'LocalAddress' = "LocalSubnet";
                #'RemoteAddress' = "LocalSubnet"; # not sure if this is needed
                'Direction' = 'Inbound';
                'Protocol' = 'TCP';
                'LocalPort' = $portSSIS
                'Action' = 'Allow'
                'Profile' = $networkProfile
                'Enabled' = 'True'; 
            };
    #>
        'SSRS' =
            @{
                'DisplayName' = "SQL Reporting Services (TCP-in)";
                'Direction' = 'Inbound';
                'Protocol' = 'TCP';
                'LocalPort' = $portSSRS
                'Action' = 'Allow'
                'Profile' = $networkProfile
                'Enabled' = 'True'; 
            };

        'SSRSSSL' =
            @{
                'DisplayName' = "SQL Reporting Services SSL (TCP-in)";
                'Direction' = 'Inbound';
                'Protocol' = 'TCP';
                'LocalPort' = $portSSRSSSL
                'Action' = 'Allow'
                'Profile' = $networkProfile
                'Enabled' = 'True'; 
            };

        'SSMSBrowse' =
            @{
                'DisplayName' = "SQL Server SSMS Browse Button (UDP-in)";
                'Direction' = 'Inbound';
                'Protocol' = 'UDP';
                'LocalPort' = $portSSMSBrowse
                'Action' = 'Allow'
                'Profile' = $networkProfile
                'Enabled' = 'True'; 
            };

    }; # end $FirewallRules splat

        # debug
        <#
        $FirewallRules
        $FirewallRules.Keys
        $FirewallRules.Values
        #>

        # DEBUG
        <#
        $debugrule = "Wireless Display (TCP-In)"
        $debugrule = "SSMS"
        $debugrule = "john test"
        $debugdisplaygroup = "johntest 4"
        $debugdisplaygroup = "Wireless Display"
        #>

        #(Get-NetFirewallRule -DisplayName $debugrule).Group # not this one! returns GUID sometimes
        #(Get-NetFirewallRule -DisplayName $debugrule).DisplayGroup # debug. works
        #(Get-NetFirewallRule -DisplayName $debugrule).DisplayName # debug. works.

        #(Set-NetFirewallRule $debugruleobject).DisplayGroup = $debugdisplaygroup # error: The property 'DisplayGroup' cannot be found on this object. Verify that the property exists and can be set.

        # debug. works!
        # Get-NetFirewallRule -DisplayName $debugrule | ForEach { $_.Group = $debugdisplaygroup ; Set-NetFirewallRule -InputObject $_ } # assign to DisplayGroup. works!
    
        # debug. works!!
        #$FirewallRulesDisplayNames = ($FirewallRules.GetEnumerator() | ForEach-Object { $_.Value }).DisplayName # convert splat to regular array list to pass to Set-NetFirewallRule
            # $FirewallRulesDisplayNames # debug

        # debug. works!
        # Get-NetFirewallRule -DisplayName $FirewallRulesDisplayNames | ForEach { $_.Group = $displaygroup ; Set-NetFirewallRule -InputObject $_ } # assign to DisplayGroup. works!

    # the new way
    function Invoke-NewFirewallRule
    {
        param ($FirewallObject)
        New-NetFirewallRule @FirewallObject #-InformationAction SilentlyContinue
    }

    # the new way. add new firewall rules.
    foreach ( $rule in $FirewallRules.GetEnumerator() ) {
        $parameters = $rule.Value
        Write-Verbose "$($rule.Name) rule has these settings:"
        Write-Verbose "Rule Display Name: $($parameters.DisplayName)"
        Write-Verbose "Program: $($parameters.Program)"
        Write-Verbose "Local Address: $($parameters.LocalAddress)"
        #Write-Verbose "Remote Address: $($parameters.RemoteAddress)" # not sure if this is needed
        Write-Verbose "Direction: $($parameters.Direction)"
        Write-Verbose "Protocol: $($parameters.Protocol)"
        Write-Verbose "Port: $($parameters.LocalPort)"
        Write-Verbose "Action: $($parameters.Action)"
        Write-Verbose "Profile: $($parameters.Profile)"
        Write-Verbose "Enabled: $($parameters.Enabled)"
        Write-Verbose ""
        Invoke-NewFirewallRule -FirewallObject $parameters #-DisplayGroup $displayGroup
        #Invoke-NewFirewallRule -FirewallObject @parameters -DisplayGroup $displayGroup # not this one
        #Invoke-FirewallRule @rule # splatting, by passing a hash table with a @ prefix and not a $, which means "unwrap my key value pairs to parameters and their values if they are named the same" - @ck
        Write-Host "Added firewall rule: $($rule.Name)"
    }

    # the new way. assign Display Group, outside the foreach loop and outside the Invoke-NewFirewallRule function so that it doesn't try to assign display group to rules that haven't been created yet.
    $FirewallRulesDisplayNames = ($FirewallRules.GetEnumerator() | ForEach-Object { $_.Value }).DisplayName # convert splat to regular array list to pass to Set-NetFirewallRule
    Write-Host "Setting Display Group to ""$displaygroup"" for the added rules. Please wait a moment..."
    Get-NetFirewallRule -DisplayName $FirewallRulesDisplayNames | ForEach { $_.Group = $displaygroup ; Set-NetFirewallRule -InputObject $_ }

            <# the old way, from https://ryanmangansitblog.com/2013/05/01/powershell-script-for-sql-firewall-rules/
            # Enable SQL Server (Database Engine) Ports
            New-NetFirewallRule -DisplayName "SQL Server Database Engine (TCP-in)" -Direction Inbound –Protocol TCP –LocalPort $portDbEngine -Action allow -Profile $networkProfile -Enabled True
            Get-NetFirewallRule -DisplayName "SQL Server Database Engine (TCP-in)" | ForEach { $_.Group = $displayGroup ; Set-NetFirewallRule -InputObject $_ } # assign to DisplayGroup

            New-NetFirewallRule -DisplayName "SQL Dedicated Admin Connection (DAC) (TCP-in)" -Direction Inbound –Protocol TCP –LocalPort 1434 -Action allow -Profile $networkProfile -Enabled True
            Get-NetFirewallRule -DisplayName "SQL Dedicated Admin Connection (DAC) (TCP-in)" | ForEach { $_.Group = $displayGroup ; Set-NetFirewallRule -InputObject $_ } # assign to DisplayGroup

            New-NetFirewallRule -DisplayName "SQL Browser Service (UDP-in)" -Direction Inbound –Protocol UDP –LocalPort 1434 -Action allow -Profile $networkProfile -Enabled True # needed for named instances for SQL Database Engine
            Get-NetFirewallRule -DisplayName "SQL Browser Service (UDP-in)" | ForEach { $_.Group = $displayGroup ; Set-NetFirewallRule -InputObject $_ } # assign to DisplayGroup

            New-NetFirewallRule -DisplayName "SQL Service Broker (TCP-in)" -Direction Inbound –Protocol TCP –LocalPort 4022 -Action allow -Profile $networkProfile -Enabled True
                # SELECT name, protocol_desc, port, state_desc FROM sys.tcp_endpoints WHERE type_desc = 'SERVICE_BROKER'
            Get-NetFirewallRule -DisplayName "SQL Service Broker (TCP-in)" | ForEach { $_.Group = $displayGroup ; Set-NetFirewallRule -InputObject $_ } # assign to DisplayGroup

            New-NetFirewallRule -DisplayName "SQL Debugger/RPC (TCP-in)" -Direction Inbound –Protocol TCP –LocalPort 135 -Action allow -Profile $networkProfile -Enabled True # also covers SSIS
            Get-NetFirewallRule -DisplayName "SQL Debugger/RPC (TCP-in)" | ForEach { $_.Group = $displayGroup ; Set-NetFirewallRule -InputObject $_ } # assign to DisplayGroup


            # Enable SQL Server Analysis Services (SSAS) Ports
            New-NetFirewallRule -DisplayName "SQL Analysis Services (TCP-in)" -Direction Inbound –Protocol TCP –LocalPort 2383 -Action allow -Profile $networkProfile -Enabled True
            Get-NetFirewallRule -DisplayName "SQL Analysis Services (TCP-in)" | ForEach { $_.Group = $displayGroup ; Set-NetFirewallRule -InputObject $_ } # assign to DisplayGroup

            New-NetFirewallRule -DisplayName "SQL Browser Service (TCP-in)" -Direction Inbound –Protocol TCP –LocalPort 2382 -Action allow -Profile $networkProfile -Enabled True # also needed for "Power Pivot" named instance for SharePoint and any other named SSAS instances
            Get-NetFirewallRule -DisplayName "SQL Browser Service (TCP-in)" | ForEach { $_.Group = $displayGroup ; Set-NetFirewallRule -InputObject $_ } # assign to DisplayGroup


            # Enable SQL Server Integration Services (SSIS)
            New-NetFirewallRule -DisplayName "SQL Integration Services (TCP-in)" -Direction Inbound –Protocol TCP –LocalPort 135 -Action allow -Profile $networkProfile -Enabled True # technically a dupe of SQL Debugger/RPC (TCP-in)
            Get-NetFirewallRule -DisplayName "SQL Integration Services (TCP-in)" | ForEach { $_.Group = $displayGroup ; Set-NetFirewallRule -InputObject $_ } # assign to DisplayGroup

            New-NetFirewallRule -DisplayName "SQL Integration Services MsDtsSrvr.exe (TCP-in)" -Program $ssispath -LocalAddress LocalSubnet -Direction Inbound –Protocol TCP –LocalPort 135 -Action allow -Profile $networkProfile -Enabled True #-RemoteAddress LocalSubnet # technically a dupe of SQL Debugger/RPC (TCP-in)
            Get-NetFirewallRule -DisplayName "SQL Integration Services MsDtsSrvr.exe (TCP-in)" | ForEach { $_.Group = $displayGroup ; Set-NetFirewallRule -InputObject $_ } # assign to DisplayGroup


            # Enable SQL Server Reporting Services (SSRS) Ports
            New-NetFirewallRule -DisplayName "SQL Reporting Services (TCP-in)" -Direction Inbound –Protocol TCP –LocalPort 80 -Action allow -Profile $networkProfile -Enabled True # also covers SQL Database Engine isntances running over an HTTP endpoint
            Get-NetFirewallRule -DisplayName "SQL Reporting Services (TCP-in)" | ForEach { $_.Group = $displayGroup ; Set-NetFirewallRule -InputObject $_ } # assign to DisplayGroup

            New-NetFirewallRule -DisplayName "SQL Reporting Services SSL (TCP-in)" -Direction Inbound –Protocol TCP –LocalPort 443 -Action allow -Profile $networkProfile -Enabled True # also covers SQL Database Engine isntances running over an HTTPS endpoint
            Get-NetFirewallRule -DisplayName "SQL Reporting Services SSL (TCP-in)" | ForEach { $_.Group = $displayGroup ; Set-NetFirewallRule -InputObject $_ } # assign to DisplayGroup


            # Enable Miscellaneous Applications
            New-NetFirewallRule -DisplayName "SQL Server SSMS Browse Button (UDP-in)" -Direction Inbound –Protocol UDP –LocalPort 1433 -Action allow -Profile $networkProfile -Enabled True
            Get-NetFirewallRule -DisplayName "SQL Server SSMS Browse Button (UDP-in)" | ForEach { $_.Group = $displayGroup ; Set-NetFirewallRule -InputObject $_ } # assign to DisplayGroup


            # Enable Windows Firewall
            Set-NetFirewallProfile -DefaultInboundAction Block -DefaultOutboundAction Allow -NotifyOnListen True -AllowUnicastResponseToMulticast True -Enabled True
            #>

    } # end process
} # end function New-DbaFirewallRule