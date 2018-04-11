#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
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
            Tags: ServerInfo
            Author: Shawn Melton (@wsmelton | http://blog.wsmelton.info)

            Website: https: //dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Get-DbaComputerSystem

        .EXAMPLE
            Get-DbaComputerSystem

            Returns information about the local computer's computer system

        .EXAMPLE
            Get-DbaComputerSystem -ComputerName sql2016

            Returns information about the sql2016's computer system

        .EXAMPLE
            Get-DbaComputerSystem -ComputerName sql2016 -IncludeAws

            Returns information about the sql2016's computer system and includes additional properties around the EC2 instance.
    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $true)]
        [Alias("cn", "host", "Server")]
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [switch]$IncludeAws,
        [switch][Alias('Silent')]
        $EnableException
    )
    process {
        foreach ($computer in $ComputerName) {
            try {
                Write-Message -Level Verbose -Message "Attempting to connect to $computer"
                $server = Resolve-DbaNetworkName -ComputerName $computer.ComputerName -Credential $Credential

                $computerResolved = $server.FullComputerName

                if (!$computerResolved) {
                    Stop-Function -Message "Unable to resolve hostname of $computer. Skipping." -Continue
                }

                if (Test-Bound "Credential") {
                    $computerSystem = Get-DbaCmObject -ClassName Win32_ComputerSystem -ComputerName $computerResolved -Credential $Credential
                }
                else {
                    $computerSystem = Get-DbaCmObject -ClassName Win32_ComputerSystem -ComputerName $computerResolved
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
                    $isAws = Invoke-Command2 -ComputerName $computerResolved -Credential $Credential -ScriptBlock { ((Invoke-WebRequest -TimeoutSec 15 -Uri 'http://169.254.169.254').StatusCode) -eq 200 } -Raw

                    if ($isAws) {
                        $scriptBlock = {
                            [PSCustomObject]@{
                                AmiId                 = (Invoke-WebRequest -Uri 'http://169.254.169.254/latest/meta-data/ami-id').Content
                                IamRoleArn            = ((Invoke-WebRequest -Uri 'http://169.254.169.254/latest/meta-data/iam/info').Content | ConvertFrom-Json).InstanceProfileArn
                                InstanceId            = (Invoke-WebRequest -Uri 'http://169.254.169.254/latest/meta-data/instance-id').Content
                                InstanceType          = (Invoke-WebRequest -Uri 'http://169.254.169.254/latest/meta-data/instance-type').Content
                                AvailabilityZone      = (Invoke-WebRequest -Uri 'http://169.254.169.254/latest/meta-data/placement/availability-zone').Content
                                PublicHostname        = (Invoke-WebRequest -Uri 'http://169.254.169.254/latest/meta-data/public-hostname').Content
                            }
                        }
                        $awsProps = Invoke-Command2 -ComputerName $computerResolved -Credential $Credential -ScriptBlock $scriptBlock
                    }
                    else {
                        Write-Message -Level Warning -Message "$computerResolved was not found to be an EC2 instance. Verify http://169.254.169.254 is accessible on the computer."
                    }
                }
                $inputObject = [PSCustomObject]@{
                    ComputerName                 = $computerResolved
                    Domain                       = $computerSystem.Domain
                    DomainRole                   = $domainRole
                    Manufacturer                 = $computerSystem.Manufacturer
                    Model                        = $computerSystem.Model
                    SystemFamily                 = $computerSystem.SystemFamily
                    SystemSkuNumber              = $computerSystem.SystemSKUNumber
                    SystemType                   = $computerSystem.SystemType
                    NumberLogicalProcessors      = $computerSystem.NumberOfLogicalProcessors
                    NumberProcessors             = $computerSystem.NumberOfProcessors
                    IsHyperThreading             = $isHyperThreading
                    TotalPhysicalMemory          = [DbaSize]$computerSystem.TotalPhysicalMemory
                    IsDaylightSavingsTime        = $computerSystem.EnableDaylightSavingsTime
                    DaylightInEffect             = $computerSystem.DaylightInEffect
                    DnsHostName                  = $computerSystem.DNSHostName
                    IsSystemManagedPageFile      = $computerSystem.AutomaticManagedPagefile
                    AdminPasswordStatus          = $adminPasswordStatus
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
            }
            catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Target $computer -Continue
            }
        }
    }
}