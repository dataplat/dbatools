function Get-DbaInstanceProtocol {
    <#
    .SYNOPSIS
        Retrieves SQL Server network protocol configuration and status from target computers.

    .DESCRIPTION
        Retrieves the configuration and status of SQL Server network protocols (TCP/IP, Named Pipes, Shared Memory, VIA) by querying the WMI ComputerManagement namespace. This is essential for troubleshooting connectivity issues, auditing network configurations for security compliance, and managing protocol settings across multiple SQL Server instances.

        The returned protocol objects include Enable() and Disable() methods, allowing you to manage protocol states directly without opening SQL Server Configuration Manager. This is particularly useful for automating security hardening by disabling unnecessary protocols or standardizing configurations across your environment.

        Requires Local Admin rights on destination computer(s).

    .PARAMETER ComputerName
        The target SQL Server instance or instances.

    .PARAMETER Credential
        Credential object used to connect to the computer as a different user.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Management, Protocol, OS
        Author: Klaas Vandenberghe (@PowerDbaKlaas)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaInstanceProtocol

    .EXAMPLE
        PS C:\> Get-DbaInstanceProtocol -ComputerName sqlserver2014a

        Gets the SQL Server related server protocols on computer sqlserver2014a.

    .EXAMPLE
        PS C:\> 'sql1','sql2','sql3' | Get-DbaInstanceProtocol

        Gets the SQL Server related server protocols on computers sql1, sql2 and sql3.

    .EXAMPLE
        PS C:\> Get-DbaInstanceProtocol -ComputerName sql1,sql2

        Gets the SQL Server related server protocols on computers sql1 and sql2.

    .EXAMPLE
        PS C:\> (Get-DbaInstanceProtocol -ComputerName sql1 | Where-Object { $_.DisplayName -eq 'Named Pipes' }).Disable()

        Disables the VIA ServerNetworkProtocol on computer sql1.
        If successful, return code 0 is shown.
    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline)]
        [Alias("cn", "host", "Server")]
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [switch]$EnableException
    )
    process {
        foreach ($Computer in $ComputerName.ComputerName) {
            $Server = Resolve-DbaNetworkName -ComputerName $Computer -Credential $Credential
            if ($Server.FullComputerName) {
                $Computer = $server.FullComputerName
                Write-Message -Level Verbose -Message "Getting SQL Server namespace on $computer"

                $cmNamespace = 'root\Microsoft\SQLServer'
                try {
                    $cmGetInstanceParams = @{
                        ComputerName = $Computer
                        Credential   = $Credential
                        Namespace    = $cmNamespace
                        Query        = "SELECT * FROM __NAMESPACE WHERE Name Like 'ComputerManagement%'"
                        ErrorAction  = 'Stop'
                    }
                    $namespaces = Get-DbaCmObject @cmGetInstanceParams
                    Write-Message -Level Verbose -Message "Successfully retrieved namespaces from $Computer. Total found: $($namespaces.Count)"
                } catch {
                    Stop-Function -Message "Failed to retrieve ComputerManagement namespace" -Category ConnectionError -ErrorRecord $_ -Target $Computer -Continue
                }
                if ($namespaces) {
                    try {
                        $instance = $namespaces | Where-Object { (Get-DbaCmObject -ComputerName $Computer -Credential $Credential -Namespace "$cmNamespace\$($_.Name)" -ClassName ServerNetworkProtocol -ErrorAction Stop).count -gt 0 } | Sort-Object Name -Descending | Select-Object -First 1
                        Write-Message -Level Verbose -Message "Successfully retrieved ServerNetworkProtocol data from $Computer"
                    } catch {
                        Stop-Function -Message "Failed to retrieve Network Protcol data" -ErrorRecord $_ -Target $Computer -Continue
                    }
                } else {
                    Stop-Function -Message "No ComputerManagement namespaces found" -Target $Computer -Continue
                }
                if ($instance.Name) {
                    $instanceName = $instance.Name
                    Write-Message -Level Verbose -Message "Getting Cim class ServerNetworkProtocol in Namespace $instanceName on $Computer"
                    try {
                        $prot = Get-DbaCmObject -ComputerName $Computer -Credential $Credential -Namespace "$cmNamespace\$($instanceName)" -ClassName ServerNetworkProtocol -ErrorAction Stop

                        $prot | Add-Member -Force -MemberType ScriptMethod -Name Enable -Value { Invoke-CimMethod -MethodName SetEnable -InputObject $this }
                        $prot | Add-Member -Force -MemberType ScriptMethod -Name Disable -Value { Invoke-CimMethod -MethodName SetDisable -InputObject $this }
                        foreach ($protocol in $prot) { Select-DefaultView -InputObject $protocol -Property 'PSComputerName as ComputerName', 'InstanceName', 'ProtocolDisplayName as DisplayName', 'ProtocolName as Name', 'MultiIpConfigurationSupport as MultiIP', 'Enabled as IsEnabled' }
                    } catch {
                        Write-Message -Level Warning -Message "Issue gathering ServerNetworkProtocol data on $Computer"
                    }
                } else {
                    Write-Message -Level Warning -Message "No ComputerManagement Namespace on $Computer. Please note that this function is available from SQL 2005 up."
                }
            } else {
                Write-Message -Level Warning -Message "Failed to connect to $Computer"
            }
        }
    }
}