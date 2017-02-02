[cmdletbinding()]
param(
	[Parameter(Mandatory = $false)]
	[string[]]$Servername,
	[Parameter(Mandatory = $false)]
	[string[]]$AccountName,

    [Parameter(Mandatory = $true)]
    [PSCredential]$Credential
)

begin {
    #$domain = ([System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()).Name

    if ($AccountName -like "*\*") {
        Write-Verbose "Account name provided in in domain\user format, stripping out domain info..."
        $serviceaccount = ($AccountName.split("\"))[1]
    }
    if ($AccountName -like "*@") {
        Write-Verbose "Account name provided in in user@domain format, stripping out domain info..."
        $AccountName = ($AccountName.split("@"))[0]
    }
}

process {
    $spns = @()
    if ($AccountName)
    {
        $root = ([ADSI]"LDAP://RootDSE").defaultNamingContext
        $adsearch = New-Object System.DirectoryServices.DirectorySearcher
        $domain = New-Object -TypeName System.DirectoryServices.DirectoryEntry -ArgumentList ("LDAP://" + $root) ,$($Credential.UserName),$($Credential.GetNetworkCredential().password)        
        $adsearch.SearchRoot = $domain
        $adsearch.Filter = $("(&(samAccountName={0}))" -f $AccountName)
        Write-Verbose "Looking for account $accountname..."
        $Result = $adsearch.FindOne()


        $results = $ADObject.FindAll()

        ForEach ($s in $results.Properties.serviceprincipalname) {
            $spn = [pscustomobject] @{
                SearchTerm = $accountName
                SPN = $s
            }
            $spns += $spn
        }

    }

    if ($ServerName)
    {
        $spnsForServer = .\Test-DbaServicePrincipalName.ps1 -Servername $Servername -Credential $Credential
        ForEach ($s in $spnsForServer | Where-Object {$_.IsSet -eq $true}) {
            $spn = [pscustomobject] @{
                SearchTerm = $serverName
                SPN = $s.RequiredSPN
            }
            $spns += $spn
        }
    }
}

end {
    return $spns
}