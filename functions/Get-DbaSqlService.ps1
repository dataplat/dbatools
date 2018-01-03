function Get-DbaSqlService {
    <#
    .SYNOPSIS
    Gets the SQL Server related services on a computer.

    .DESCRIPTION
    Gets the SQL Server related services on one or more computers.

    Requires Local Admin rights on destination computer(s).

    .PARAMETER ComputerName
    The SQL Server (or server in general) that you're connecting to. This command handles named instances.

    .PARAMETER InstanceName
    Only returns services that belong to the specific instances.

    .PARAMETER Credential
    Credential object used to connect to the computer as a different user.

    .PARAMETER Type
    Use -Type to collect only services of the desired SqlServiceType.
    Can be one of the following: "Agent","Browser","Engine","FullText","SSAS","SSIS","SSRS"

    .PARAMETER ServiceName
    Can be used to specify service names explicitly, without looking for service types/instances.

    .PARAMETER EnableException
    By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
    Tags:
    Author: Klaas Vandenberghe ( @PowerDBAKlaas )

    dbatools PowerShell module (https://dbatools.io)
    Copyright (C) 2016 Chrissy LeMaire
    License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

    .LINK
    https://dbatools.io/Get-DbaSqlService

    .EXAMPLE
    Get-DbaSqlService -ComputerName sqlserver2014a

    Gets the SQL Server related services on computer sqlserver2014a.

    .EXAMPLE
    'sql1','sql2','sql3' | Get-DbaSqlService

    Gets the SQL Server related services on computers sql1, sql2 and sql3.

    .EXAMPLE
    Get-DbaSqlService -ComputerName sql1,sql2 | Out-Gridview

    Gets the SQL Server related services on computers sql1 and sql2, and shows them in a grid view.

    .EXAMPLE
    Get-DbaSqlService -ComputerName $MyServers -Type SSRS

    Gets the SQL Server related services of type "SSRS" (Reporting Services) on computers in the variable MyServers.

    .EXAMPLE
    $services = Get-DbaSqlService -ComputerName sql1 -Type Agent,Engine
    $services.ChangeStartMode('Manual')

    Gets the SQL Server related services of types Sql Agent and DB Engine on computer sql1 and changes their startup mode to 'Manual'.

    .EXAMPLE
    (Get-DbaSqlService sql1 -Type Engine).Restart($true)

    Calls a Restart method for each Engine service on computer sql1 with -Force option.
#>
    [CmdletBinding(DefaultParameterSetName = "Search")]
    Param (
        [parameter(ValueFromPipeline = $true, Position = 1)]
        [Alias("cn", "host", "Server")]
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [Parameter(ParameterSetName = "Search")]
        [Alias("Instance")]
        [string[]]$InstanceName,
        [PSCredential]$Credential,
        [Parameter(ParameterSetName = "Search")]
        [ValidateSet("Agent", "Browser", "Engine", "FullText", "SSAS", "SSIS", "SSRS")]
        [string[]]$Type,
        [Parameter(ParameterSetName = "ServiceName")]
        [string[]]$ServiceName,
        [switch][Alias('Silent')]$EnableException
    )

    BEGIN {
        #Dictionary to transform service type IDs into the names from Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer.Services.Type
        $ServiceIdMap = @(
            @{ Name = "Engine"; Id = 1 },
            @{ Name = "Agent"; Id = 2 },
            @{ Name = "FullText"; Id = 3, 9 },
            @{ Name = "SSIS"; Id = 4 },
            @{ Name = "SSAS"; Id = 5 },
            @{ Name = "SSRS"; Id = 6 },
            @{ Name = "Browser"; Id = 7 },
            @{ Name = "Unknown"; Id = 8 }
        )
        if ($PsCmdlet.ParameterSetName -match 'Search') {
            if ($Type) {
                $searchClause = ""
                foreach ($itemType in $Type) {
                    foreach ($id in ($ServiceIdMap | Where-Object { $_.Name -eq $itemType }).Id) {
                        if ($searchClause) { $searchClause += ' OR ' }
                        $searchClause += "SQLServiceType = $id"
                    }
                }
            }
            else {
                $searchClause = "SQLServiceType > 0"
            }
        }
        elseif ($PsCmdlet.ParameterSetName -match 'ServiceName') {
            if ($ServiceName) {
                $searchClause = ""
                foreach ($sn in $ServiceName) {
                    if ($searchClause) { $searchClause += ' OR ' }
                    $searchClause += "ServiceName = '$sn'"
                }
            }
            else {
                $searchClause = "SQLServiceType > 0"
            }
        }
    }
    PROCESS {
        foreach ($Computer in $ComputerName.ComputerName) {
            $Server = Resolve-DbaNetworkName -ComputerName $Computer -Credential $credential
            if ($Server.ComputerName) {
                $Computer = $server.ComputerName
                Write-Message -Level VeryVerbose -Message "Getting SQL Server namespace on $Computer" -Target $Computer
                try { $namespaces = Get-DbaCmObject -ComputerName $Computer -NameSpace root\Microsoft\SQLServer -Query "Select Name FROM __NAMESPACE WHERE Name Like 'ComputerManagement%'" -EnableException -Credential $credential | Sort-Object Name -Descending }
                catch { }
                if ($namespaces) {
                    $servicesTemp = @()

                    ForEach ($namespace in $namespaces) {
                        try {
                            Write-Message -Level Verbose -Message "Getting Cim class SqlService in Namespace $($namespace.Name) on $Computer." -Target $Computer
                            foreach ($service in (Get-DbaCmObject -ComputerName $Computer -Namespace "root\Microsoft\SQLServer\$($namespace.Name)" -Query "SELECT * FROM SqlService WHERE $searchClause" -EnableException -Credential $credential)) {
                                $servicesTemp += New-Object PSObject -Property @{
                                    Name      = $service.ServiceName
                                    Namespace = $namespace.Name
                                    Service   = $service
                                }
                            }
                        }
                        catch {
                            Write-Message -Level Verbose -EnableException $EnableException -Message "Failed to acquire services from namespace $($namespace.Name)." -Target $Computer
                        }
                    }

                    $services = ($servicesTemp | Group-Object Name | ForEach-Object { $_.Group | Sort-Object Namespace -Descending | Select-Object -First 1 }).Service

                    if ($services) {
                        Write-Message -Level Verbose -EnableException $EnableException -Message "Creating output objects"
                        ForEach ($service in $services) {
                            Add-Member -Force -InputObject $service -MemberType NoteProperty -Name ComputerName -Value $service.HostName
                            Add-Member -Force -InputObject $service -MemberType NoteProperty -Name ServiceType -Value ($ServiceIdMap | Where-Object { $_.Id -contains $service.SQLServiceType }).Name
                            Add-Member -Force -InputObject $service -MemberType NoteProperty -Name State -Value $(switch ($service.State) { 1 { 'Stopped' } 2 { 'Start Pending' }  3 { 'Stop Pending' } 4 { 'Running' } })
                            Add-Member -Force -InputObject $service -MemberType NoteProperty -Name StartMode -Value $(switch ($service.StartMode) { 1 { 'Unknown' } 2 { 'Automatic' }  3 { 'Manual' } 4 { 'Disabled' } })

                            if ($service.ServiceName -in ("MSSQLSERVER", "SQLSERVERAGENT", "ReportServer", "MSSQLServerOLAPService")) {
                                $instance = "MSSQLSERVER"
                            }
                            else {
                                if ($service.ServiceType -in @("Agent", "Engine", "SSRS", "SSAS")) {
                                    if ($service.ServiceName.indexof('$') -ge 0) {
                                        $instance = $service.ServiceName.split('$')[1]
                                    }
                                    else {
                                        $instance = "Unknown"
                                    }
                                }
                                else {
                                    $instance = ""
                                }
                            }
                            $priority = switch ($service.ServiceType) {
                                "Engine" { 200 }
                                default { 100 }
                            }
                            #If only specific instances are selected
                            if (!$InstanceName -or $instance -in $InstanceName) {
                                #Add other properties and methods
                                Add-Member -Force -InputObject $service -NotePropertyName InstanceName -NotePropertyValue $instance
                                Add-Member -Force -InputObject $service -NotePropertyName ServicePriority -NotePropertyValue $priority
                                Add-Member -Force -InputObject $service -MemberType ScriptMethod -Name "Stop" -Value {
                                    Param ([bool]$Force = $false)
                                    Stop-DbaSqlService -ServiceCollection $this -Force:$Force
                                }
                                Add-Member -Force -InputObject $service -MemberType ScriptMethod -Name "Start" -Value { Start-DbaSqlService -ServiceCollection $this }
                                Add-Member -Force -InputObject $service -MemberType ScriptMethod -Name "Restart" -Value {
                                    Param ([bool]$Force = $false)
                                    Restart-DbaSqlService -ServiceCollection $this -Force:$Force
                                }
                                Add-Member -Force -InputObject $service -MemberType ScriptMethod -Name "ChangeStartMode" -Value {
                                    Param (
                                        [parameter(Mandatory = $true)]
                                        [string]$Mode
                                    )
                                    $supportedModes = @("Automatic", "Manual", "Disabled")
                                    if ($Mode -notin $supportedModes) {
                                        Stop-Function -Message ("Incorrect mode '$Mode'. Use one of the following values: {0}" -f ($supportedModes -join ' | ')) -EnableException $false -FunctionName 'Get-DbaSqlService'
                                        Return
                                    }
                                    Set-ServiceStartMode -ServiceCollection $this -Mode $Mode -ErrorAction Stop
                                    $this.StartMode = $Mode
                                }
                                Select-DefaultView -InputObject $service -Property ComputerName, ServiceName, ServiceType, InstanceName, DisplayName, StartName, State, StartMode -TypeName DbaSqlService
                            }
                        }
                    }
                    else {
                        Stop-Function -EnableException $EnableException -Message "No Sql Services found on $Computer" -Continue
                    }
                }
                else {
                    Stop-Function -EnableException $EnableException -Message "No ComputerManagement Namespace on $Computer. Please note that this function is available from SQL 2005 up." -Continue
                }
            }
            else {
                Stop-Function -EnableException $EnableException -Message "Failed to connect to $Computer" -Continue
            }
        }
    }
}
