namespace Sqlcollaborative.Dbatools.Utility
{
    /// <remarks>
    /// The word in a SQL Server password hash is a LITTLE ENDIAN version number of the password. Before 2012 it was 
    /// 0x0100 or 1. After 2012 it is 0x0200 or 2.
    /// </remarks>>
    public enum DbaPasswordHashVersion : ushort
    {
        /// <summary>Sql Server 2000</summary>
        Sql2000 = 1,
        /// <summary>Sql Server 2005</summary>
        Sql2005 = 1,
        /// <summary>Sql Server 2008</summary>
        Sql2008 = 1,
        /// <summary>Sql Server 2012</summary>
        Sql2012 = 2,
        /// <summary>Sql Server 2016</summary>
        Sql2016 = 2,
        /// <summary>Sql Server 2017</summary>
        Sql2017 = 2,
    }
}