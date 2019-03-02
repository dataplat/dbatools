function Invoke-CommandWithFallback {
    <#
    When credentials are specified, it is possible that the chosen protocol would fail to connect with them.
    Fallback will use PSSessionConfiguration to create a session configuration on a remote machine that uses
    provided set of credentials by default. A new session will be created that uses this custom configuration
    and performs remote execution under defined set of credentials without relying on delegation or CredSSP.
    #>
    param (
        [DbaInstanceParameter]$ComputerName = $env:COMPUTERNAME,
        [object]$Credential,
        [scriptblock]$ScriptBlock,
        [object[]]$ArgumentList,
        [parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [ValidateSet('Default', 'Basic', 'Negotiate', 'NegotiateWithImplicitCredential', 'Credssp', 'Digest', 'Kerberos')]
        [string]$Authentication = 'Default',
        [switch]$Raw,
        [version]$RequiredPSVersion
    )
    try {
        Invoke-Command2 @PSBoundParameters
    } catch [System.Management.Automation.Remoting.PSRemotingTransportException] {
        # This implements a fallback scenario, when both credentials and fallback are specified, but the original session has failed
        # Credentials will be passed on through a default session and used as a default PSSessionConfiguration
        if ($Credential) {
            Write-Message -Level Verbose -Message "Initial connection to $($ComputerName.ComputerName) through $Authentication protocol unsuccessful, falling back to PSSession configurations | $($_.Exception.Message)"
            $configuration = Register-RemoteSessionConfiguration -Computer $ComputerName.ComputerName -Credential $Credential -Name dbatoolsInvokeCommandWithFailback -Confirm:$false
            if ($configuration.Successful) {
                $PSBoundParameters.ConfigurationName = $configuration.Name
                $PSBoundParameters.Authentication = 'Default'
                try {
                    Invoke-Command2 @PSBoundParameters
                } catch {
                    throw $_
                } finally {
                    # Unregister PSRemote configurations once completed. It's slow, but necessary - otherwise we're gonna have leftover junk with credentials on a remote
                    $unreg = Unregister-RemoteSessionConfiguration -ComputerName $ComputerName.ComputerName -Credential $Credential -Name $configuration.Name -Confirm:$false
                    if (-not $unreg.Successful) {
                        Write-Warning -Message "Failed to unregister PSSession Configurations on $($ComputerName.ComputerName) | $($configuration.Status)"
                    }
                }
            } else {
                Stop-Function -Message "Both $Authentication and failback connections failed | $($configuration.Status)" -ErrorRecord $_ -EnableException $true
            }
        } else {
            #default behavior
            throw $_
        }
    } catch {
        throw $_
    }
}