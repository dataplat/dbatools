using System;
using System.Collections.Generic;
using System.Linq;
using System.Management.Automation;
using System.Text;
using System.Threading.Tasks;
using Sqlcollaborative.Dbatools.Utility;

namespace Sqlcollaborative.Dbatools.Parameter
{
    /// <summary>
    /// Parameter class that only accepts live SMO Databases
    /// </summary>
    public class DbaDatabaseSmoParameter
    {
        #region Fields of Contract
        /// <summary>
        /// The original object passed to the parameter
        /// </summary>
        [ParameterContract(ParameterContractType.Field, ParameterContractBehavior.Mandatory)]
        public object InputObject { get; set; }

        /// <summary>
        /// The SMO Database Object
        /// </summary>
        [ParameterContract(ParameterContractType.Field, ParameterContractBehavior.Mandatory)]
        public object Database { get; set; }

        /// <summary>
        /// The name of the database
        /// </summary>
        [ParameterContract(ParameterContractType.Field, ParameterContractBehavior.Mandatory)]
        public string Name { get; set; }
        #endregion Fields of Contract

        #region Constructors
        /// <summary>
        /// Accepts anything and tries to convert it to a live SMO Database object
        /// </summary>
        /// <param name="Item">The item to convert</param>
        public DbaDatabaseSmoParameter(object Item)
        {
            if (Item == null)
                throw new ArgumentException("Input must not be null!");

            InputObject = Item;
            PSObject tempInput = new PSObject(Item);

            if (tempInput.TypeNames.Contains("Microsoft.SqlServer.Management.Smo.Database"))
            {
                Database = Item;
                Name = (string)tempInput.Properties["Name"].Value;
                return;
            }

            foreach (PSPropertyInfo prop in tempInput.Properties)
            {
                if (UtilityHost.IsLike(prop.Name, "Database") && (prop.Value != null))
                {
                    PSObject tempDB = new PSObject(prop.Value);

                    if (tempDB.TypeNames.Contains("Microsoft.SqlServer.Management.Smo.Database"))
                    {
                        Database = prop.Value;
                        Name = (string)tempDB.Properties["Name"].Value;
                        return;
                    }
                }
            }

            throw new ArgumentException("Cannot interpret input as SMO Database object");
        }
        #endregion Constructors

        /// <summary>
        /// Overrides the regular tostring to show something pleasant and useful
        /// </summary>
        /// <returns>The name of the database</returns>
        public override string ToString()
        {
            return Name;
        }
    }
}
