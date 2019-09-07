function Get-DbaReportingService {
    <#
    .SYNOPSIS
        Gets the SQL Server Reporting Services on a computer.

    .DESCRIPTION
        Gets the SQL Server Reporting Services on one or more computers.

        Requires Local Admin rights on destination computer(s).

    .PARAMETER ComputerName
        The target SQL Server instance or instances.

    .PARAMETER InstanceName
        Only returns services that belong to the specific instances.

    .PARAMETER Credential
        Credential object used to connect to the computer as a different user.

    .PARAMETER ServiceName
        Can be used to specify service names explicitly, without looking for service types/instances.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Service, SqlServer, Instance, Connect
        Author: Kirill Kravtsov ( @nvarscar )

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaService

    .EXAMPLE
        PS C:\> Get-DbaReportingService -ComputerName sqlserver2014a

        Gets the Reporting Services on computer sqlserver2014a.

    .EXAMPLE
        PS C:\> $cred = Get-Credential WindowsUser
        PS C:\> Get-DbaReportingService -ComputerName sql1,sql2 -Credential $cred  | Out-GridView

        Gets the Reporting Services on computers sql1 and sql2 via the user WindowsUser, and shows them in a grid view.

    .EXAMPLE
        PS C:\> Get-DbaReportingService -ComputerName sql1,sql2 -InstanceName MSSQLSERVER

        Gets the Reporting Services related to the default instance MSSQLSERVER on computers sql1 and sql2.

    .EXAMPLE
        PS C:\> $MyServers =  Get-Content .\servers.txt
        PS C:\> Get-DbaReportingService -ComputerName $MyServers -ServiceName MSSQLSERVER,SQLSERVERAGENT

        Gets the Reporting Services with ServiceName MSSQLSERVER or SQLSERVERAGENT  for all the servers that are stored in the file. Every line in the file can only contain one hostname for a server.

    .EXAMPLE
        PS C:\> $services = Get-DbaReportingService -ComputerName sql1
        PS C:\> $services.ChangeStartMode('Manual')

        Gets the Reporting Services on computer sql1 and changes their startup mode to 'Manual'.

    .EXAMPLE
        PS C:\> (Get-DbaReportingService -ComputerName sql1).Restart($true)

        Calls a Restart method for each Reporting service on computer sql1.

    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline, Position = 1)]
        [Alias("cn", "host", "Server")]
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [Alias("Instance")]
        [string[]]$InstanceName,
        [PSCredential]$Credential,
        [string[]]$ServiceName,
        [switch]$EnableException
    )
    begin {
        $searchClause = ""
        #If filtering by service name create a dynamic WHERE clause
        if ($ServiceName) {
            $searchClause = " WHERE ServiceName = '$($ServiceName -join "' OR ServiceName = '")'"
        }
    }
    process {
        foreach ($computer in $ComputerName) {
            $serviceArray = @()
            Write-Message -Level VeryVerbose -Message "Getting Reporting Server namespace on $Computer" -Target $Computer
            try {
                $namespaces = Get-DbaCmObject -ComputerName $Computer -NameSpace root\Microsoft\SQLServer\ReportServer -Query "Select Name FROM __NAMESPACE" -EnableException -Credential $credential
            } catch {
                Write-Message -Level Verbose -Message "No SQLServer\ReportServer Namespace on $Computer. Please note that this function is available from SQL 2005 up."
                return
            }
            # querying SqlService namespace
            ForEach ($namespace in $namespaces) {
                Write-Message -Level Verbose -Message "Getting version from the namespace $($namespace.Name) on $Computer." -Target $Computer
                try {
                    $namespaceVersion = Get-DbaCmObject -ComputerName $Computer -Namespace "root\Microsoft\SQLServer\ReportServer\$($namespace.Name)" -Query "SELECT Name FROM __NAMESPACE" -EnableException
                } catch {
                    Stop-Function -EnableException $EnableException -Message "No version Namespace on $Computer. Please note that this function is available from SQL 2005 up." -Continue
                }
                try {
                    $cimQuery = "SELECT * FROM MSReportServer_ConfigurationSetting" + $searchClause
                    $services = Get-DbaCmObject -ComputerName $Computer -Namespace "root\Microsoft\SQLServer\ReportServer\$($namespace.Name)\$($namespaceVersion.Name)\Admin" -Query $cimQuery -EnableException
                } catch {
                    Stop-Function -EnableException $EnableException -Message "Failed to acquire services from namespace $($namespace.Name)\$($namespaceVersion.Name)." -Target $Computer -ErrorRecord $_ -Continue
                }
                ForEach ($service in $services) {
                    if ($serviceArray -notcontains $($service.ServiceName)) {
                        if (!$InstanceName -or $service.InstanceName -in $InstanceName) {
                            #Add other properties and methods
                            Add-Member -Force -InputObject $service -MemberType NoteProperty -Name ServiceType -Value 'SSRS'
                            Add-Member -Force -InputObject $service -MemberType AliasProperty -Name StartName -Value WindowsServiceIdentityActual

                            try {
                                $service32 = Get-DbaCmObject -ComputerName $Computer -Namespace "root\cimv2" -Query "SELECT * FROM Win32_Service WHERE Name = '$($service.ServiceName)'" -EnableException
                            } catch {
                                Stop-Function -EnableException $EnableException -Message "Failed to acquire services32" -Target $Computer -ErrorRecord $_ -Continue
                            }
                            Add-Member -Force -InputObject $service -MemberType NoteProperty -Name ComputerName -Value $service32.SystemName
                            Add-Member -Force -InputObject $service -MemberType NoteProperty -Name State -Value $service32.State
                            $startMode = switch ($service32.StartMode) {
                                Auto { 'Automatic' } #Replacing for consistency to match other SQL Services
                                default { $_ }
                            }
                            Add-Member -Force -InputObject $service -MemberType NoteProperty -Name StartMode -Value $startMode
                            Add-Member -Force -InputObject $service -MemberType NoteProperty -Name DisplayName -Value $service32.DisplayName
                            Add-Member -Force -InputObject $service -NotePropertyName ServicePriority -NotePropertyValue 100
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
                            $defaults = "ComputerName", "ServiceName", "ServiceType", "InstanceName", "DisplayName", "StartName", "State", "StartMode"
                            Select-DefaultView -InputObject $service -Property $defaults -TypeName DbaSqlService
                        }
                        $serviceArray += $service.ServiceName
                    }
                }
            }
        }
    }
    end {

    }
}