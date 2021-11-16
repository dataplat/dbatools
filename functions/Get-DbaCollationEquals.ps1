Function Get-DbaCollationEquals
{
	param( [string]$Collation, [string]$String1, [string]$string2,[Microsoft.SqlServer.Management.Smo.Server]$SqlInstance )
	if ( -not $SqlInstance ) {
		$SqlInstance = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Server
	}
	return $SqlInstance.getStringComparer($Collation).Compare($string1, $string2) -eq 0
}
