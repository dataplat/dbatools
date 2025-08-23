function Get-DbaService {
    <#
    .SYNOPSIS
        Retrieves SQL Server-related Windows services from local or remote computers.

    .DESCRIPTION
        Retrieves detailed information about SQL Server-related Windows services across one or more computers, including Database Engine, SQL Agent, Reporting Services, Analysis Services, Integration Services, and other SQL Server components. This function replaces manual service management tasks by providing a unified view of service status, startup modes, and service accounts across your SQL Server environment.

        Particularly useful for inventory management, troubleshooting service issues, and performing bulk service operations across multiple servers. The function can filter by service type, instance name, or specific service names, and optionally includes advanced properties like SQL Server version and service pack levels.

        Returns service objects with built-in methods for common operations like Start(), Stop(), Restart(), and ChangeStartMode(), eliminating the need to use separate service management commands.

        Requires Local Admin rights on destination computer(s).

    .PARAMETER ComputerName
        Specifies the target computer(s) to retrieve SQL Server services from. Accepts computer names, IP addresses, or FQDN.
        Use this when you need to check service status across multiple servers in your environment.

    .PARAMETER InstanceName
        Filters results to show only services belonging to the specified SQL Server instance names.
        Use this when you need to focus on specific instances rather than all SQL Server services on the target computers.

    .PARAMETER SqlInstance
        Use a combination of computername and instancename to get the SQL Server related services for specific instances on specific computers.

        Parameters ComputerName and InstanceName will be ignored if SqlInstance is used.

    .PARAMETER Credential
        Credential object used to connect to the computer as a different user.

    .PARAMETER Type
        Filters results to specific SQL Server service types such as Database Engine, SQL Agent, or Reporting Services.
        Use this when troubleshooting specific service types or performing targeted service management operations. Can be one of the following: "Agent", "Browser", "Engine", "FullText", "SSAS", "SSIS", "SSRS", "PolyBase", "Launchpad"

    .PARAMETER ServiceName
        Specifies exact Windows service names to retrieve, bypassing automatic service discovery.
        Use this when you know the specific service names and want to avoid the overhead of scanning for all SQL Server services.

    .PARAMETER AdvancedProperties
        Includes additional service properties such as SQL Server version, service pack level, SKU name, and cluster information.
        Use this when you need detailed service information for inventory, compliance, or troubleshooting purposes. Note that this adds processing time to the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Service, SqlServer, Instance, Connect
        Author: Klaas Vandenberghe (@PowerDbaKlaas)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaService

    .EXAMPLE
        PS C:\> Get-DbaService -ComputerName sqlserver2014a

        Gets the SQL Server related services on computer sqlserver2014a.

    .EXAMPLE
        PS C:\> 'sql1','sql2','sql3' | Get-DbaService -AdvancedProperties

        Gets the SQL Server related services on computers sql1, sql2 and sql3. Includes Advanced Properties from the SqlServiceAdvancedProperty Namespace

    .EXAMPLE
        PS C:\> $cred = Get-Credential WindowsUser
        PS C:\> Get-DbaService -ComputerName sql1,sql2 -Credential $cred  | Out-GridView

        Gets the SQL Server related services on computers sql1 and sql2 via the user WindowsUser, and shows them in a grid view.

    .EXAMPLE
        PS C:\> Get-DbaService -ComputerName sql1,sql2 -InstanceName MSSQLSERVER

        Gets the SQL Server related services related to the default instance MSSQLSERVER on computers sql1 and sql2.

    .EXAMPLE
        PS C:\> Get-DbaService -SqlInstance sql1, sql1\test, sql2\test

        Gets the SQL Server related services related to the default instance MSSQLSERVER on computers sql1, the named instances test on sql1 and sql2.

    .EXAMPLE
        PS C:\> Get-DbaService -ComputerName $MyServers -Type SSRS

        Gets the SQL Server related services of type "SSRS" (Reporting Services) on computers in the variable MyServers.

    .EXAMPLE
        PS C:\> $MyServers =  Get-Content .\servers.txt
        PS C:\> Get-DbaService -ComputerName $MyServers -ServiceName MSSQLSERVER,SQLSERVERAGENT

        Gets the SQL Server related services with ServiceName MSSQLSERVER or SQLSERVERAGENT  for all the servers that are stored in the file. Every line in the file can only contain one hostname for a server.

    .EXAMPLE
        PS C:\> $services = Get-DbaService -ComputerName sql1 -Type Agent,Engine
        PS C:\> $services.ChangeStartMode('Manual')

        Gets the SQL Server related services of types Sql Agent and DB Engine on computer sql1 and changes their startup mode to 'Manual'.

    .EXAMPLE
        PS C:\> (Get-DbaService -ComputerName sql1 -Type Engine).Restart($true)

        Calls a Restart method for each Engine service on computer sql1.

    #>
    [CmdletBinding(DefaultParameterSetName = "Search")]
    param (
        [parameter(ValueFromPipeline, Position = 1)]
        [Alias("cn", "host", "Server")]
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [Parameter(ParameterSetName = "Search")]
        [Alias("Instance")]
        [string[]]$InstanceName,
        [Parameter(ParameterSetName = "Search")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$Credential,
        [Parameter(ParameterSetName = "Search")]
        [ValidateSet("Agent", "Browser", "Engine", "FullText", "SSAS", "SSIS", "SSRS", "PolyBase", "Launchpad")]
        [string[]]$Type,
        [Parameter(ParameterSetName = "ServiceName")]
        [string[]]$ServiceName,
        [switch]$AdvancedProperties,
        [switch]$EnableException
    )

    begin {
        if ($SqlInstance) {
            # If SqlInstance is used, we select the list of computers for ComputerName
            $ComputerName = $SqlInstance | Select-Object -ExpandProperty ComputerName -Unique
        }

        #Dictionary to transform service type IDs into the names from Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer.Services.Type
        $ServiceIdMap = @(
            @{ Name = "Engine"; Id = 1 },
            @{ Name = "Agent"; Id = 2 },
            @{ Name = "FullText"; Id = 3, 9 },
            @{ Name = "SSIS"; Id = 4 },
            @{ Name = "SSAS"; Id = 5 },
            @{ Name = "SSRS"; Id = 6 },
            @{ Name = "Browser"; Id = 7 },
            @{ Name = "PolyBase"; Id = 10, 11 },
            @{ Name = "Launchpad"; Id = 12 },
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
            } else {
                $searchClause = "SQLServiceType > 0"
            }
        } elseif ($PsCmdlet.ParameterSetName -match 'ServiceName') {
            if ($ServiceName) {
                $searchClause = ""
                foreach ($sn in $ServiceName) {
                    if ($searchClause) { $searchClause += ' OR ' }
                    $searchClause += "ServiceName = '$sn'"
                }
            } else {
                $searchClause = "SQLServiceType > 0"
            }
        }
    }
    process {
        foreach ($computer in $ComputerName.ComputerName) {
            if ($SqlInstance) {
                # If SqlInstance is used, we select the list of instances for the current computer
                $InstanceName = $SqlInstance | Where-Object ComputerName -eq $computer | Select-Object -ExpandProperty InstanceName
            }

            try {
                $resolvedComputerName = (Resolve-DbaNetworkName -ComputerName $computer -Credential $Credential -EnableException).FullComputerName
                $null = Get-DbaCmObject -ComputerName $resolvedComputerName -Credential $Credential -Namespace root\Microsoft -ClassName __NAMESPACE -EnableException
            } catch {
                Stop-Function -Message "Failed to resolve or to connect to $computer." -Target $computer -Category ConnectionError -ErrorRecord $_ -Continue
            }

            $namespaces = @( )
            $services = @()
            $outputServices = @()

            if (!$Type -or 'SSRS' -in $Type) {
                Write-Message -Level Verbose -Message "Getting SQL Reporting Server services on $computer" -Target $computer
                $reportingServices = Get-DbaReportingService -ComputerName $resolvedComputerName -InstanceName $InstanceName -Credential $Credential -ServiceName $ServiceName
                $outputServices += $reportingServices
            }

            Write-Message -Level Verbose -Message "Getting SQL Server namespaces on $computer" -Target $computer
            try {
                $namespaces = Get-DbaCmObject -ComputerName $resolvedComputerName -Credential $Credential -Namespace root\Microsoft\SQLServer -Query "Select Name FROM __NAMESPACE WHERE Name Like 'ComputerManagement%'" -EnableException | Sort-Object Name -Descending
                Write-Message -Level Verbose -Message "The following namespaces have been found: $($namespaces.Name -join ', ')."
            } catch {
                Write-Message -Level Verbose -Message "No namespaces found in relevant namespace on $computer."
            }

            foreach ($namespace in $namespaces) {
                try {
                    Write-Message -Level Verbose -Message "Getting Cim class SqlService in Namespace $($namespace.Name) on $computer." -Target $computer
                    foreach ($service in (Get-DbaCmObject -ComputerName $resolvedComputerName -Credential $Credential -Namespace "root\Microsoft\SQLServer\$($namespace.Name)" -Query "SELECT * FROM SqlService WHERE $searchClause" -EnableException)) {
                        Write-Message -Level Verbose -Message "Found service $($service.ServiceName) in namespace $($namespace.Name)."
                        $services += $service
                    }
                    # Use highest namespace available, so break if services have been found
                    break
                } catch {
                    Write-Message -Level Verbose -Message "Failed to acquire services from namespace $($namespace.Name)." -Target $Computer -ErrorRecord $_
                }
            }

            # Remove services returned by the SSRS namespace
            $services = $services | Where-Object ServiceName -notin $reportingServices.ServiceName

            # Add custom properties and methods to the service objects
            foreach ($service in $services) {
                Add-Member -Force -InputObject $service -MemberType NoteProperty -Name ComputerName -Value $service.HostName
                Add-Member -Force -InputObject $service -MemberType NoteProperty -Name ServiceType -Value ($ServiceIdMap | Where-Object { $_.Id -contains $service.SQLServiceType }).Name
                Add-Member -Force -InputObject $service -MemberType NoteProperty -Name State -Value $(switch ($service.State) { 1 { 'Stopped' } 2 { 'Start Pending' }  3 { 'Stop Pending' } 4 { 'Running' } })
                Add-Member -Force -InputObject $service -MemberType NoteProperty -Name StartMode -Value $(switch ($service.StartMode) { 1 { 'Unknown' } 2 { 'Automatic' }  3 { 'Manual' } 4 { 'Disabled' } })

                if ($service.ServiceName -in ("MSSQLSERVER", "SQLSERVERAGENT", "ReportServer", "MSSQLServerOLAPService", "MSSQLFDLauncher", "SQLPBDMS", "SQLPBENGINE", "MSSQLLAUNCHPAD")) {
                    $instance = "MSSQLSERVER"
                } else {
                    if ($service.ServiceType -in @("Agent", "Engine", "SSRS", "SSAS", "FullText", "PolyBase", "Launchpad")) {
                        if ($service.ServiceName.indexof('$') -ge 0) {
                            $instance = $service.ServiceName.split('$')[1]
                        } else {
                            $instance = "Unknown"
                        }
                    } else {
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
                        param ([bool]$Force = $false)
                        Stop-DbaService -InputObject $this -Force:$Force
                    }
                    Add-Member -Force -InputObject $service -MemberType ScriptMethod -Name "Start" -Value { Start-DbaService -InputObject $this }
                    Add-Member -Force -InputObject $service -MemberType ScriptMethod -Name "Restart" -Value {
                        param ([bool]$Force = $false)
                        Restart-DbaService -InputObject $this -Force:$Force
                    }
                    Add-Member -Force -InputObject $service -MemberType ScriptMethod -Name "ChangeStartMode" -Value {
                        param (
                            [parameter(Mandatory)]
                            [string]$Mode
                        )
                        $supportedModes = @("Automatic", "Manual", "Disabled")
                        if ($Mode -notin $supportedModes) {
                            Stop-Function -Message ("Incorrect mode '$Mode'. Use one of the following values: {0}" -f ($supportedModes -join ' | ')) -EnableException $false -FunctionName 'Get-DbaService'
                            Return
                        }
                        Set-ServiceStartMode -InputObject $this -Mode $Mode -ErrorAction Stop
                        $this.StartMode = $Mode
                    }

                    if ($AdvancedProperties) {
                        $namespaceValue = $service.CimClass.ToString().ToUpper().Replace(":SQLSERVICE", "").Replace("ROOT/MICROSOFT/SQLSERVER/", "")
                        $serviceAdvancedProperties = Get-DbaCmObject -ComputerName $Computer -Namespace "root\Microsoft\SQLServer\$($namespaceValue)" -Query "SELECT * FROM SqlServiceAdvancedProperty WHERE ServiceName = '$($service.ServiceName)'"

                        Add-Member -Force -InputObject $service -MemberType NoteProperty -Name Version -Value ($serviceAdvancedProperties | Where-Object PropertyName -eq 'VERSION' ).PropertyStrValue
                        Add-Member -Force -InputObject $service -MemberType NoteProperty -Name SPLevel -Value ($serviceAdvancedProperties | Where-Object PropertyName -eq 'SPLEVEL' ).PropertyNumValue
                        Add-Member -Force -InputObject $service -MemberType NoteProperty -Name SkuName -Value ($serviceAdvancedProperties | Where-Object PropertyName -eq 'SKUNAME' ).PropertyStrValue

                        $ClusterServiceTypeList = @(1, 2, 5, 7)
                        if ($ClusterServiceTypeList -contains $service.SQLServiceType) {
                            Add-Member -Force -InputObject $service -MemberType NoteProperty -Name Clustered -Value ($serviceAdvancedProperties | Where-Object PropertyName -eq 'CLUSTERED' ).PropertyNumValue
                            Add-Member -Force -InputObject $service -MemberType NoteProperty -Name VSName -Value ($serviceAdvancedProperties | Where-Object PropertyName -eq 'VSNAME' ).PropertyStrValue
                        } else {
                            Add-Member -Force -InputObject $service -MemberType NoteProperty -Name Clustered -Value ''
                            Add-Member -Force -InputObject $service -MemberType NoteProperty -Name VSName -Value ''
                        }
                    }
                    $outputServices += $service
                }
            }
            if ($AdvancedProperties) {
                $defaults = "ComputerName", "ServiceName", "ServiceType", "InstanceName", "DisplayName", "StartName", "State", "StartMode", "Version", "SPLevel", "SkuName", "Clustered", "VSName"
            } else {
                $defaults = "ComputerName", "ServiceName", "ServiceType", "InstanceName", "DisplayName", "StartName", "State", "StartMode"
            }
            if ($outputServices) {
                $outputServices | Select-DefaultView -Property $defaults -TypeName DbaSqlService
            } else {
                Write-Message -Level Verbose -Message "No services found in relevant namespaces on $computer."
            }
        }
    }
}