Function Test-SqlCompletedStatement
{
	param (
		[object]$server,
		[string]$dbname,
		[string]$sql,
		[int]$sqlpid
	)
	
	if ($sqlpid) { " and session_id = $sqlpid" }
	$sql = $sql.Replace("'", "''")
	
	$testsql = "select sqltext.text FROM sys.dm_exec_requests req CROSS APPLY sys.dm_exec_sql_text(sql_handle) AS sqltext where text = '$sql' $sqlpid"
	
	if ($server.ConnectionContext.ExecuteScalar($testsql) -ne $null)
	{
		return $false
	}
	else
	{
		return $true
	}
}