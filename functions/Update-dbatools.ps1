Function Update-dbatools
{
<# 
.SYNOPSIS 
Exported function. Updates dbatools. Deletes current copy and replaces it with freshest copy.

.EXAMPLE
Update-dbatools
#>	
	
	Invoke-Expression (Invoke-WebRequest -UseBasicParsing https://raw.githubusercontent.com/sqlcollaborative/dbatools/master/install.ps1).Content
}