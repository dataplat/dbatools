Register-DbaMessageTransform -TargetType 'Sqlcollaborative.Dbatools.Parameter.DbaInstanceParameter' -ScriptBlock {
    $args[0].FullSmoName
}
Register-DbaMessageTransform -TargetType 'Microsoft.SqlServer.Management.Smo.Server' -ScriptBlock {
    ([Sqlcollaborative.Dbatools.Parameter.DbaInstanceParameter]$args[0]).FullSmoName
}

Register-DbaMessageTransform -ExceptionTypeFilter '*' -ScriptBlock {
    if ($args[0] -is [Microsoft.Data.SqlClient.SqlException]) { return $args[0] }

    $item = $args[0]
    while ($item.InnerException) {
        $item = $item.InnerException
        if ($item -is [Microsoft.Data.SqlClient.SqlException]) { return $item }
    }

    return $args[0]
}