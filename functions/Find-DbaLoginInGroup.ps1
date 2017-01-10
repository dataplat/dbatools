function Find-DbaLoginInGroup
{
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[string[]]$SqlInstance,
		[System.Management.Automation.PSCredential]$SqlCredential,
        [string]$Login
	)
    begin
    {
        try
        {
            Add-Type -AssemblyName  System.DirectoryServices.AccountManagement;
        }
        catch
        {
            Write-warning "Failed to load Assembly needed" 
            break
        }
    }
    
    PROCESS
    {
       foreach ($Instance in $SqlInstance)
        {
            try
	        {
	            Write-Verbose "Connecting to $Instance"
                $server = Connect-SqlServer -SqlServer $Instance -SqlCredential $sqlcredential
	        }
	        catch
	        {
	            Write-Warning "Failed to connect to: $Instance"
                break
	        }

            $AdGroups = $server.Logins | Where {$_.LoginType -eq "WindowsGroup" -and $_.Name -ne "BUILTIN\Administrators" -and $_.Name -notlike "*NT SERVICE*"}
            $ADGroupOut = @()
            foreach ($AdGroup in $AdGroups)
            {
                try 
                {
                    $domain = $AdGroup.Name.Split("\")[0]
                    $ads = New-Object System.DirectoryServices.AccountManagement.PrincipalContext('Domain', $domain) 
                    [string] $groupName = $AdGroup.Name
                    $group = [System.DirectoryServices.AccountManagement.GroupPrincipal]::FindByIdentity($ads, $groupName); 
                    foreach ($member in $group.Members)
                    {
                        $adout = [PSCustomObject]@{
		                    GroupName = $AdGroup.Name
                            Login = $member.SamAccountName
                            }
		                $ADGroupOut += $adout
                    } 
                }
                catch
                {
                    write-warning "error connecting to $AdGroup, run Test-DbaValidLogin to ensure the group exist in AD"
                }
            }

            Foreach ($l in $Login)
            {
                $username = $l.Split("\")[1]
                write-verbose "Looking for $username"
                $FoundYou = @()
                try 
                {    
                    $FoundYou = $ADGroupOut | Where {$_.Login -eq $username} 
         
                }
                catch
                {
                    write-warning "Failed to find Login: $Login as a Login or in a group connecting to server: $server"
                    break
                }
                #$FoundYou
                foreach($gf in $FoundYou)
                {
                
                    $gfRole = $gf.GroupName
                    $output = [PSCustomObject]@{
                        ComputerName = $server.NetName
                        SqlInstance = $server.InstanceName
                        Login = $l
                        Member = $gfRole
                    }
                    Select-DefaultField -InputObject $output -Property ComputerName, SqlInstance, Login, Member  
                }
            } # foreach login
        } # foreach
    } # process
}