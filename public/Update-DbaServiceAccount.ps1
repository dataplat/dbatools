function Update-DbaServiceAccount {
    <#
    .SYNOPSIS
        Changes the service account or password for SQL Server Engine and Agent services.

    .DESCRIPTION
        Updates the service account credentials or changes just the password for SQL Server Engine and Agent services. When changing the service account, the affected service will be automatically restarted to apply the changes. Password-only updates don't require a restart unless you want the changes to take effect immediately.

        This function handles the complexities of SQL Server service management, including removing and reapplying network certificates during account changes to prevent SSL connection issues. It supports changing from local system accounts to domain accounts, rotating passwords for compliance, and updating multiple services across multiple instances.

        Supports SQL Server Engine and Agent services on supported SQL Server versions. Other services like Reporting Services or Analysis Services are not supported and may cause the function to fail on older SQL Server versions.

    .PARAMETER ComputerName
        The target SQL Server instance or instances.

    .PARAMETER Credential
        Windows Credential with permission to log on to the server running the SQL instance

    .PARAMETER InputObject
        A collection of services. Basically, any object that has ComputerName and ServiceName properties. Can be piped from Get-DbaService.

    .PARAMETER ServiceName
        A name of the service on which the action is performed. E.g. MSSQLSERVER or SqlAgent$INSTANCENAME

    .PARAMETER ServiceCredential
        Windows Credential object under which the service will be setup to run. Cannot be used with -Username. For local service accounts use one of the following usernames with empty password:
        LOCALSERVICE
        NETWORKSERVICE
        LOCALSYSTEM

    .PARAMETER PreviousPassword
        An old password of the service account. Optional when run under local admin privileges.

    .PARAMETER SecurePassword
        New password of the service account. The function will ask for a password if not specified. MSAs and local system accounts will ignore the password.

    .PARAMETER Username
        Username of the service account. Cannot be used with -ServiceCredential. For local service accounts use one of the following usernames omitting the -SecurePassword parameter:
        LOCALSERVICE
        NETWORKSERVICE
        LOCALSYSTEM

    .PARAMETER NoRestart
        Do not immediately restart the service after changing the password.

        **Note that the changes will not go into effect until you restart the SQL Services**

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .LINK
        https://dbatools.io/Update-DbaServiceAccount

    .NOTES
        Tags: Service, SqlServer, Instance, Connect
        Author: Kirill Kravtsov (@nvarscar)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires Local Admin rights on destination computer(s).

    .EXAMPLE
        PS C:\> $SecurePassword = (Get-Credential NoUsernameNeeded).Password
        PS C:\> Update-DbaServiceAccount -ComputerName sql1 -ServiceName 'MSSQL$MYINSTANCE' -SecurePassword $SecurePassword

        Changes the current service account's password of the service MSSQL$MYINSTANCE to 'Qwerty1234'

    .EXAMPLE
        PS C:\> $cred = Get-Credential
        PS C:\> Get-DbaService sql1 -Type Engine,Agent -Instance MYINSTANCE | Update-DbaServiceAccount -ServiceCredential $cred

        Requests credentials from the user and configures them as a service account for the SQL Server engine and agent services of the instance sql1\MYINSTANCE

    .EXAMPLE
        PS C:\> Update-DbaServiceAccount -ComputerName sql1,sql2 -ServiceName 'MSSQLSERVER','SQLSERVERAGENT' -Username NETWORKSERVICE

        Configures SQL Server engine and agent services on the machines sql1 and sql2 to run under Network Service system user.

    .EXAMPLE
        PS C:\> Get-DbaService sql1 -Type Engine -Instance MSSQLSERVER | Update-DbaServiceAccount -Username 'MyDomain\sqluser1'

        Configures SQL Server engine service on the machine sql1 to run under MyDomain\sqluser1. Will request user to input the account password.


    .EXAMPLE
        PS C:\> Get-DbaService sql1 -Type Engine -Instance MSSQLSERVER | Update-DbaServiceAccount -Username 'MyDomain\sqluser1' -NoRestart

        Configures SQL Server engine service on the machine sql1 to run under MyDomain\sqluser1. Will request user to input the account password.

        Will not restart, which means the changes will not go into effect, so you will still have to restart during your planned outage window.

    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = "ServiceName" )]
    param (
        [parameter(ParameterSetName = "ServiceName")]
        [Alias("cn", "host", "Server")]
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [parameter(ValueFromPipeline, Mandatory, ParameterSetName = "InputObject")]
        [Alias("ServiceCollection")]
        [object[]]$InputObject,
        [parameter(ParameterSetName = "ServiceName", Position = 1, Mandatory)]
        [Alias("Name", "Service")]
        [string[]]$ServiceName,
        [Alias("User")]
        [string]$Username,
        [PSCredential]$ServiceCredential,
        [securestring]$PreviousPassword = (New-Object System.Security.SecureString),
        [Alias("Password", "NewPassword")]
        [securestring]$SecurePassword = (New-Object System.Security.SecureString),
        [switch]$NoRestart,
        [switch]$EnableException
    )
    begin {
        $svcCollection = @()
        $scriptAccountChange = {
            $service = $wmi.Services[$args[0]]
            $service.SetServiceAccount($args[1], $args[2])
            $service.Alter()
        }
        $scriptPasswordChange = {
            $service = $wmi.Services[$args[0]]
            $service.ChangePassword($args[1], $args[2])
            $service.Alter()
        }
        #Check parameters
        if ($Username) {
            $actionType = 'Account'
            if ($ServiceCredential) {
                Stop-Function -EnableException $EnableException -Message "You cannot specify both -UserName and -ServiceCredential parameters" -Category InvalidArgument
                return
            }
            #System logins should not have a domain name, whitespaces or passwords
            $trimmedUsername = (Split-Path $Username -Leaf).Trim().Replace(' ', '')
            #Request password input if password was not specified and account is not MSA or system login
            if ($SecurePassword.Length -eq 0 -and $PSBoundParameters.Keys -notcontains 'SecurePassword' -and $trimmedUsername -notin 'NETWORKSERVICE', 'LOCALSYSTEM', 'LOCALSERVICE' -and $Username.EndsWith('$') -eq $false -and $Username.StartsWith('NT Service\') -eq $false) {
                $SecurePassword = Read-Host -Prompt "Input new password for account $UserName" -AsSecureString
                $NewPassword2 = Read-Host -Prompt "Repeat password" -AsSecureString
                if ((New-Object System.Management.Automation.PSCredential ("user", $SecurePassword)).GetNetworkCredential().Password -ne `
                    (New-Object System.Management.Automation.PSCredential ("user", $NewPassword2)).GetNetworkCredential().Password) {
                    Stop-Function -Message "Passwords do not match" -Category InvalidArgument -EnableException $EnableException
                    return
                }
            }
            $currentCredential = New-Object System.Management.Automation.PSCredential ($Username, $SecurePassword)
        } elseif ($ServiceCredential) {
            $actionType = 'Account'
            $currentCredential = $ServiceCredential
        } else {
            $actionType = 'Password'
        }
        if ($actionType -eq 'Account') {
            #System logins should not have a domain name, whitespaces or passwords
            $credUserName = (Split-Path $currentCredential.UserName -Leaf).Trim().Replace(' ', '')
            #Check for system logins and replace the Credential object to simplify passing localsystem-like login names
            if ($credUserName -in 'NETWORKSERVICE', 'LOCALSYSTEM', 'LOCALSERVICE') {
                $currentCredential = New-Object System.Management.Automation.PSCredential ($credUserName, (New-Object System.Security.SecureString))
            }
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }

        if ($PsCmdlet.ParameterSetName -match 'ServiceName') {
            foreach ($Computer in $ComputerName.ComputerName) {
                $Server = Resolve-DbaNetworkName -ComputerName $Computer -Credential $credential
                if ($Server.FullComputerName) {
                    foreach ($service in $ServiceName) {
                        $svcCollection += [psobject]@{
                            ComputerName = $server.FullComputerName
                            ServiceName  = $service
                        }
                    }
                } else {
                    Stop-Function -EnableException $EnableException -Message "Failed to connect to $Computer" -Continue
                }
            }
        } elseif ($PsCmdlet.ParameterSetName -match 'InputObject') {
            foreach ($service in $InputObject) {
                if ($service.ServiceName -eq 'PowerBIReportServer') {
                    Stop-Function -Message "PowerBIReportServer service is not supported, skipping." -Continue
                } else {
                    $Server = Resolve-DbaNetworkName -ComputerName $service.ComputerName -Credential $credential
                    if ($Server.FullComputerName) {
                        $svcCollection += [psobject]@{
                            ComputerName = $Server.FullComputerName
                            ServiceName  = $service.ServiceName
                        }
                    } else {
                        Stop-Function -EnableException $EnableException -Message "Failed to connect to $($service.FullComputerName)" -Continue
                    }
                }
            }
        }

    }
    end {
        foreach ($svc in $svcCollection) {
            if ($serviceObject = Get-DbaService -ComputerName $svc.ComputerName -ServiceName $svc.ServiceName -Credential $Credential -EnableException:$EnableException) {
                $outMessage = $outStatus = $agent = $null
                if ($actionType -eq 'Password' -and $SecurePassword.Length -eq 0) {
                    $currentPassword = Read-Host -Prompt "New password for $($serviceObject.StartName) ($($svc.ServiceName) on $($svc.ComputerName))" -AsSecureString
                    $currentPassword2 = Read-Host -Prompt "Repeat password" -AsSecureString
                    if ((New-Object System.Management.Automation.PSCredential ("user", $currentPassword)).GetNetworkCredential().Password -ne `
                        (New-Object System.Management.Automation.PSCredential ("user", $currentPassword2)).GetNetworkCredential().Password) {
                        Stop-Function -Message "Passwords do not match. This service will not be updated" -Category InvalidArgument -EnableException $EnableException -Continue
                    }
                } else {
                    $currentPassword = $SecurePassword
                }
                if ($serviceObject.ServiceType -eq 'Engine') {
                    #Get SQL Agent running status
                    $agent = Get-DbaService -ComputerName $svc.ComputerName -Type Agent -InstanceName $serviceObject.InstanceName
                }
                if ($PsCmdlet.ShouldProcess($serviceObject, "Changing account information for service $($svc.ServiceName) on $($svc.ComputerName)")) {
                    try {
                        if ($actionType -eq 'Account') {
                            # Test if a certificate is used. If so, remove it and set it again later.
                            $certificate = $null
                            if ($serviceObject.ServiceType -eq 'Engine') {
                                $sqlInstance = $svc.ComputerName
                                if ($svc.ServiceName -ne 'MSSQLSERVER') {
                                    $instanceName = $svc.ServiceName -replace '^MSSQL\$', ''
                                    $sqlInstance += '\' + $instanceName
                                }
                                # We try to get the certificate, but don't fail in case we are not able to.
                                $certificate = Get-DbaNetworkConfiguration -SqlInstance $sqlInstance -Credential $Credential -OutputType Certificate
                                if ($certificate.Thumbprint) {
                                    Write-Message -Level Verbose -Message "Removing certificate from service $($svc.ServiceName) on $($svc.ComputerName)"
                                    $null = Remove-DbaNetworkCertificate -SqlInstance $sqlInstance -Credential $Credential -EnableException
                                }
                            }
                            Write-Message -Level Verbose -Message "Attempting an account change for service $($svc.ServiceName) on $($svc.ComputerName)"
                            $null = Invoke-ManagedComputerCommand -ComputerName $svc.ComputerName -Credential $Credential -ScriptBlock $scriptAccountChange -ArgumentList @($svc.ServiceName, $currentCredential.UserName, $currentCredential.GetNetworkCredential().Password) -EnableException:$EnableException
                            $outMessage = "The login account for the service has been successfully set."
                            if ($certificate.Thumbprint) {
                                Write-Message -Level Verbose -Message "Setting certificate for service $($svc.ServiceName) on $($svc.ComputerName)"
                                $null = Set-DbaNetworkCertificate -SqlInstance $sqlInstance -Credential $Credential -Thumbprint $certificate.Thumbprint -EnableException
                            }
                        } elseif ($actionType -eq 'Password') {
                            Write-Message -Level Verbose -Message "Attempting a password change for service $($svc.ServiceName) on $($svc.ComputerName)"
                            $null = Invoke-ManagedComputerCommand -ComputerName $svc.ComputerName -Credential $Credential -ScriptBlock $scriptPasswordChange -ArgumentList @($svc.ServiceName, (New-Object System.Management.Automation.PSCredential ("user", $PreviousPassword)).GetNetworkCredential().Password, (New-Object System.Management.Automation.PSCredential ("user", $currentPassword)).GetNetworkCredential().Password) -EnableException:$EnableException
                            $outMessage = "The password has been successfully changed."
                        }
                        $outStatus = 'Successful'
                    } catch {
                        $outStatus = 'Failed'
                        $outMessage = $_.Exception.Message
                        if ($certificate.Thumbprint) {
                            # Depending on where the process failed, the certificate might be already removed but not yet set again.
                            $outMessage += " Please check if certificate with thumbprint $($certificate.Thumbprint) is still in place."
                        }
                        Stop-Function -Message $outMessage -Continue
                    }
                } else {
                    $outStatus = 'Successful'
                    $outMessage = 'No changes made - running in -WhatIf mode.'
                }
                if ($serviceObject.ServiceType -eq 'Engine' -and $actionType -eq 'Account' -and $outStatus -eq 'Successful' -and $agent.State -eq 'Running' -and -not $NoRestart) {
                    #Restart SQL Agent after SQL Engine has been restarted
                    if ($PsCmdlet.ShouldProcess($serviceObject, "Starting SQL Agent after Engine account change on $($svc.ComputerName)")) {
                        $res = Start-DbaService -ComputerName $svc.ComputerName -Type Agent -InstanceName $serviceObject.InstanceName
                        if ($res.Status -ne 'Successful') {
                            Write-Message -Level Warning -Message "Failed to restart SQL Agent after changing credentials. $($res.Message)"
                        }
                    }
                }
                if ($NoRestart) {
                    Write-Message -Level Warning -Message "Changes will not go into effect until you restart. Please restart the services manually during your designated outage window."
                }
                $serviceObject = Get-DbaService -ComputerName $svc.ComputerName -ServiceName $svc.ServiceName -Credential $Credential -EnableException:$EnableException
                Add-Member -Force -InputObject $serviceObject -NotePropertyName Message -NotePropertyValue $outMessage
                Add-Member -Force -InputObject $serviceObject -NotePropertyName Status -NotePropertyValue $outStatus
                Select-DefaultView -InputObject $serviceObject -Property ComputerName, ServiceName, State, StartName, Status, Message
            } Else {
                Stop-Function -Message "The service $($svc.ServiceName) has not been found on $($svc.ComputerName)" -EnableException $EnableException -Continue
            }
        }
    }
}