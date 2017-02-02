[cmdletbinding()]
param(
	[Parameter(Mandatory = $true)]
	[string]$spn,
	[Parameter(Mandatory = $true)]
	[string]$serviceaccount,
	[Parameter(Mandatory = $true)]
	[pscredential]$Credential
)

begin {
}

process {
    if ($serviceaccount -like "*\*") {
        Write-Verbose "Account provided in in domain\user format, stripping out domain info..."
        $serviceaccount = ($serviceaccount.split("\"))[1]
    }
    if ($serviceaccount -like "*@") {
        Write-Verbose "Account provided in in user@domain format, stripping out domain info..."
        $serviceaccount = ($serviceaccount.split("@"))[0]
    }

    $root = ([ADSI]"LDAP://RootDSE").defaultNamingContext
    $adsearch = New-Object System.DirectoryServices.DirectorySearcher
    $domain = New-Object -TypeName System.DirectoryServices.DirectoryEntry -ArgumentList ("LDAP://" + $root) ,$($Credential.UserName),$($Credential.GetNetworkCredential().password)        
    $adsearch.SearchRoot = $domain
    $adsearch.Filter = $("(&(samAccountName={0}))" -f $serviceaccount)
    Write-Verbose "Looking for account $serviceAccount..."
    $Result = $adsearch.FindOne()

    #did we find the server account?

    If($Result -eq $null) {
	    Write-Error "The account you specified for the SPN ($serviceAccount) doesn't exist"
    } else {
        #cool! add an spn

        $ADEntry = $Result.GetDirectoryEntry()
        $ADEntry.Properties['serviceprincipalname'].Add($spn) | Out-Null
        Write-Verbose "Added SPN $spn to samaccount $serviceaccount"
        $ADEntry.CommitChanges()


        #Don't forget delegation!
        $ADEntry = $Result.GetDirectoryEntry()
        $ADEntry.Properties['msDS-AllowedToDelegateTo'].Add($spn) | Out-Null
        Write-Verbose "Added kerberos delegation to $spn for samaccount $serviceaccount"
        $ADEntry.CommitChanges()
    }
}

end {
}

