$functions = Get-ChildItem function:\*-Dba*
foreach ($function in $functions) {
    if ($function.Parameters.Keys -contains "SqlInstance") {
        Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter SqlInstance -Name SqlInstance
    }
    if ($function.Parameters.Keys -contains "Database") {
        Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter Database -Name Database
    }
    if ($function.Parameters.Keys -contains "ExceptDatabase") {
        Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter ExceptDatabase -Name Database
    }
}