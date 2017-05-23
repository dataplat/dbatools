$functions = Get-ChildItem function:\*-Dba*
foreach ($function in $functions) {
    if ($function.Parameters.Keys -contains "SqlInstance") {
        Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter SqlInstance -Name SqlInstance
    }
    if ($function.Parameters.Keys -contains "Database") {
        Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter Database -Name Database
    }
    if ($function.Parameters.Keys -contains "ExcludeDatabase") {
        Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter ExcludeDatabase -Name Database
	}
	if ($function.Parameters.Keys -contains "Job") {
		Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter Job -Name Job
	}
	if ($function.Parameters.Keys -contains "ExcludeJob") {
		Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter ExcludeJob -Name Job
	}
	if ($function.Parameters.Keys -contains "Login") {
		Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter Login -Name Login
	}
	if ($function.Parameters.Keys -contains "ExcludeLogin") {
		Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter ExcludeLogin -Name Login
	}
}