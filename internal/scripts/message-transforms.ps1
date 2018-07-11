Register-DbaMessageTransform -TargetType 'Sqlcollaborative.Dbatools.Parameter.DbaInstanceParameter' -ScriptBlock {
    $args[0].InstanceName
}
Register-DbaMessageTransform -TargetType 'Microsoft.SqlServer.Management.Smo.Server' -ScriptBlock {
    ([Sqlcollaborative.Dbatools.Parameter.DbaInstanceParameter]$args[0]).InstanceName
}

Register-DbaMessageTransform -ExceptionTypeFilter '*' -ScriptBlock {
    if ($args[0].GetType() -is [System.Data.SqlClient.SqlException]) { return $args[0] }
    
    $item = $args[0]
    while ($item.InnerException) {
        $item = $item.InnerException
        if ($item.GetType() -is [System.Data.SqlClient.SqlException]) { return $item }
    }
    
    return $args[0]
}