using WebUntis.Core;

namespace WebUntis.Core.Tests;

public class ProductTests
{
    [Fact]
    public void NameStaysStableForThePackageIdentity()
    {
        Assert.Equal("WebUntis", Product.Name);
        Assert.False(string.IsNullOrWhiteSpace(Product.Version));
    }
}
