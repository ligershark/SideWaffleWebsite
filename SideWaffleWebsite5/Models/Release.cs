using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace SideWaffleWebsite5.Models
{
    public class Release
    {
        public string Name { get; set; }
        public string TagName { get; set; }
        public bool PreRelease { get; set; }
    }
}
