function Get-DbaComputerSystem {
    <#
    .SYNOPSIS
        Gets computer system information from the server.

    .DESCRIPTION
        Gets computer system information from the server and returns as an object.

    .PARAMETER ComputerName
        Target computer(s). If no computer name is specified, the local computer is targeted

    .PARAMETER Credential
        Alternate credential object to use for accessing the target computer(s).

    .PARAMETER IncludeAws
        If computer is hosted in AWS Infrastructure as a Service (IaaS), additional information will be included.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Server, Management
        Author: Shawn Melton (@wsmelton), https://wsmelton.github.io

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaComputerSystem

    .EXAMPLE
        PS C:\> Get-DbaComputerSystem

        Returns information about the local computer's computer system

    .EXAMPLE
        PS C:\> Get-DbaComputerSystem -ComputerName sql2016

        Returns information about the sql2016's computer system

    .EXAMPLE
        PS C:\> Get-DbaComputerSystem -ComputerName sql2016 -IncludeAws

        Returns information about the sql2016's computer system and includes additional properties around the EC2 instance.
    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline)]
        [Alias("cn", "host", "Server")]
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [switch]$IncludeAws,
        [switch]$EnableException
    )
    process {
        foreach ($computer in $ComputerName) {
            try {
                $server = Resolve-DbaNetworkName -ComputerName $computer.ComputerName -Credential $Credential

                $computerResolved = $server.FullComputerName

                if (!$computerResolved) {
                    Stop-Function -Message "Unable to resolve hostname of $computer. Skipping." -Continue
                }

                if (Test-Bound "Credential") {
                    $computerSystem = Get-DbaCmObject -ClassName Win32_ComputerSystem -ComputerName $computerResolved -Credential $Credential
                    $computerProcessor = Get-DbaCmObject -ClassName Win32_Processor -ComputerName $computerResolved -Credential $Credential
                } else {
                    $computerSystem = Get-DbaCmObject -ClassName Win32_ComputerSystem -ComputerName $computerResolved
                    $computerProcessor = Get-DbaCmObject -ClassName Win32_Processor -ComputerName $computerResolved
                }

                $adminPasswordStatus =
                switch ($computerSystem.AdminPasswordStatus) {
                    0 { "Disabled" }
                    1 { "Enabled" }
                    2 { "Not Implemented" }
                    3 { "Unknown" }
                    default { "Unknown" }
                }

                $domainRole =
                switch ($computerSystem.DomainRole) {
                    0 { "Standalone Workstation" }
                    1 { "Member Workstation" }
                    2 { "Standalone Server" }
                    3 { "Member Server" }
                    4 { "Backup Domain Controller" }
                    5 { "Primary Domain Controller" }
                }

                $isHyperThreading = $false
                if ($computerSystem.NumberOfLogicalProcessors -gt $computerSystem.NumberofProcessors) {
                    $isHyperThreading = $true
                }

                if ($IncludeAws) {
                    try {
                        $ProxiedFunc = "function Invoke-TlsRestMethod {`n" + $(Get-Item function:\Invoke-TlsRestMethod).ScriptBlock + "`n}"
                        $isAws = Invoke-Command2 -ComputerName $computerResolved -Credential $Credential -ArgumentList $ProxiedFunc -ScriptBlock {
                            Param( $ProxiedFunc )
                            . ([ScriptBlock]::Create($ProxiedFunc))
                            ((Invoke-TlsRestMethod -TimeoutSec 15 -Uri 'http://169.254.169.254').StatusCode) -eq 200
                        } -Raw
                    } catch [System.Net.WebException] {
                        $isAws = $false
                        Write-Message -Level Warning -Message "$computerResolved was not found to be an EC2 instance. Verify http://169.254.169.254 is accessible on the computer."
                    }

                    if ($isAws) {
                        $ProxiedFunc = "function Invoke-TlsRestMethod {`n" + $(Get-Item function:\Invoke-TlsRestMethod).ScriptBlock + "`n}"
                        $scriptBlock = {
                            Param( $ProxiedFunc )
                            . ([ScriptBlock]::Create($ProxiedFunc))
                            [PSCustomObject]@{
                                AmiId            = (Invoke-TlsRestMethod -Uri 'http://169.254.169.254/latest/meta-data/ami-id')
                                IamRoleArn       = ((Invoke-TlsRestMethod -Uri 'http://169.254.169.254/latest/meta-data/iam/info').InstanceProfileArn)
                                InstanceId       = (Invoke-TlsRestMethod -Uri 'http://169.254.169.254/latest/meta-data/instance-id')
                                InstanceType     = (Invoke-TlsRestMethod -Uri 'http://169.254.169.254/latest/meta-data/instance-type')
                                AvailabilityZone = (Invoke-TlsRestMethod -Uri 'http://169.254.169.254/latest/meta-data/placement/availability-zone')
                                PublicHostname   = (Invoke-TlsRestMethod -Uri 'http://169.254.169.254/latest/meta-data/public-hostname')
                            }
                        }
                        $awsProps = Invoke-Command2 -ComputerName $computerResolved -Credential $Credential -ArgumentList $ProxiedFunc -ScriptBlock $scriptBlock
                    }
                }
                $inputObject = [PSCustomObject]@{
                    ComputerName            = $computerResolved
                    Domain                  = $computerSystem.Domain
                    DomainRole              = $domainRole
                    Manufacturer            = $computerSystem.Manufacturer
                    Model                   = $computerSystem.Model
                    SystemFamily            = $computerSystem.SystemFamily
                    SystemSkuNumber         = $computerSystem.SystemSKUNumber
                    SystemType              = $computerSystem.SystemType
                    ProcessorName           = $computerProcessor.Name
                    ProcessorCaption        = $computerProcessor.Caption
                    ProcessorMaxClockSpeed  = $computerProcessor.MaxClockSpeed
                    NumberLogicalProcessors = $computerSystem.NumberOfLogicalProcessors
                    NumberProcessors        = $computerSystem.NumberOfProcessors
                    IsHyperThreading        = $isHyperThreading
                    TotalPhysicalMemory     = [DbaSize]$computerSystem.TotalPhysicalMemory
                    IsDaylightSavingsTime   = $computerSystem.EnableDaylightSavingsTime
                    DaylightInEffect        = $computerSystem.DaylightInEffect
                    DnsHostName             = $computerSystem.DNSHostName
                    IsSystemManagedPageFile = $computerSystem.AutomaticManagedPagefile
                    AdminPasswordStatus     = $adminPasswordStatus
                }
                if ($IncludeAws -and $isAws) {
                    Add-Member -Force -InputObject $inputObject -MemberType NoteProperty -Name AwsAmiId -Value $awsProps.AmiId
                    Add-Member -Force -InputObject $inputObject -MemberType NoteProperty -Name AwsIamRoleArn -Value $awsProps.IamRoleArn
                    Add-Member -Force -InputObject $inputObject -MemberType NoteProperty -Name AwsEc2InstanceId -Value $awsProps.InstanceId
                    Add-Member -Force -InputObject $inputObject -MemberType NoteProperty -Name AwsEc2InstanceType -Value $awsProps.InstanceType
                    Add-Member -Force -InputObject $inputObject -MemberType NoteProperty -Name AwsAvailabilityZone -Value $awsProps.AvailabilityZone
                    Add-Member -Force -InputObject $inputObject -MemberType NoteProperty -Name AwsPublicHostName -Value $awsProps.PublicHostname
                }
                $excludes = 'SystemSkuNumber', 'IsDaylightSavingsTime', 'DaylightInEffect', 'DnsHostName', 'AdminPasswordStatus'
                Select-DefaultView -InputObject $inputObject -ExcludeProperty $excludes
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Target $computer -Continue
            }
        }
    }
}
