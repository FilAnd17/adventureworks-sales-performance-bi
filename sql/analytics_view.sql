USE AdventureWorks2022;
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.schemas
    WHERE name = 'analytics'
)
BEGIN
    EXEC('CREATE SCHEMA analytics');
END;
GO

CREATE VIEW analytics.fact_sales AS
SELECT
    h.SalesOrderID,
    d.SalesOrderDetailID,
    CAST(h.OrderDate AS date) AS OrderDate,
    CAST(h.DueDate AS date) AS DueDate,
    CAST(h.ShipDate AS date) AS ShipDate,
    h.CustomerID,
    h.SalesPersonID,
    h.TerritoryID,
    d.ProductID,
    d.SpecialOfferID,
    h.OnlineOrderFlag,
    h.Status AS OrderStatus,
    d.OrderQty,
    d.UnitPrice,
    d.UnitPriceDiscount,
    d.LineTotal,
    CAST(d.OrderQty * d.UnitPrice AS money) AS GrossLineAmount,
    CAST(d.OrderQty * d.UnitPrice * d.UnitPriceDiscount AS money) AS DiscountAmount,
    DATEDIFF(day, h.OrderDate, h.ShipDate) AS DaysToShip
FROM Sales.SalesOrderHeader h
INNER JOIN Sales.SalesOrderDetail d
    ON h.SalesOrderID = d.SalesOrderID;
GO

CREATE VIEW analytics.dim_product AS 
SELECT
    p.ProductID,
    p.Name AS ProductName,
    p.MakeFlag,
    p.FinishedGoodsFlag,
    p.Color,
    p.StandardCost,
    p.ListPrice,
    p.Size,
    p.Weight,
    p.ProductLine,
    p.Class,
    p.Style,
    p.ProductSubCategoryID,
    ps.Name AS SubCategoryName,
    ps.ProductCategoryID,
    pc.Name AS CategoryName,
    CAST(p.SellStartDate AS date) AS SellStartDate,
    CAST(p.SellEndDate AS date) AS SellEndDate,
    CAST(p.DiscontinuedDate AS date) AS DiscontinuedDate
FROM Production.Product p
LEFT JOIN Production.ProductSubcategory ps 
    ON p.ProductSubcategoryID = ps.ProductSubcategoryID
LEFT JOIN Production.ProductCategory pc 
    ON ps.ProductCategoryID = pc.ProductCategoryID;
GO

CREATE VIEW analytics.dim_territory AS
SELECT
    TerritoryID,
    Name AS TerritoryName,
    CountryRegionCode,
    [Group] AS TerritoryGroup,
    SalesYTD,
    SalesLastYear,
    CostYTD,
    CostLastYear
FROM Sales.SalesTerritory;
GO

CREATE VIEW analytics.dim_salesperson AS
SELECT
    sp.BusinessEntityID AS SalesPersonID,
    CONCAT(p.FirstName, ' ', p.LastName) AS SalesPersonName,
    e.JobTitle,
    CAST(e.HireDate AS date) AS HireDate,
    e.CurrentFlag,
    sp.TerritoryID,
    sp.SalesQuota AS CurrentSalesQuota,
    sp.Bonus,
    sp.CommissionPct,
    sp.SalesYTD,
    sp.SalesLastYear
FROM Sales.SalesPerson sp
LEFT JOIN Person.Person p 
    ON sp.BusinessEntityID = p.BusinessEntityID
LEFT JOIN HumanResources.Employee e 
    ON sp.BusinessEntityID = e.BusinessEntityID;
GO

CREATE VIEW analytics.fact_sales_quota AS
SELECT
    BusinessEntityID AS SalesPersonID,
    CAST(QuotaDate AS date) AS QuotaDate,
    SalesQuota
FROM Sales.SalesPersonQuotaHistory;
GO

CREATE VIEW analytics.dim_date AS
WITH DateBounds AS (
    SELECT
        MIN(DateValue) AS StartDate,
        MAX(DateValue) AS EndDate
    FROM (
        SELECT CAST(OrderDate AS date) AS DateValue
        FROM Sales.SalesOrderHeader

        UNION ALL

        SELECT CAST(QuotaDate AS date) AS DateValue
        FROM Sales.SalesPersonQuotaHistory
    ) d
),
Numbers AS (
    SELECT TOP (10000)
        ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS n
    FROM sys.all_objects a
    CROSS JOIN sys.all_objects b
),
DateSeries AS (
    SELECT
        DATEADD(day, n, db.StartDate) AS [Date]
    FROM Numbers
    CROSS JOIN DateBounds db
    WHERE DATEADD(day, n, db.StartDate) <= db.EndDate
)
SELECT
    [Date],
    YEAR([Date]) AS [Year],
    DATEPART(quarter, [Date]) AS QuarterNumber,
    CONCAT('Q', DATEPART(quarter, [Date])) AS QuarterName,
    MONTH([Date]) AS MonthNumber,
    DATENAME(month, [Date]) AS MonthName,
    FORMAT([Date], 'yyyy-MM') AS YearMonth,
    DATEFROMPARTS(YEAR([Date]), MONTH([Date]), 1) AS MonthStart,
    DAY([Date]) AS DayOfMonth,
    DATENAME(weekday, [Date]) AS WeekdayName,
    DATEPART(weekday, [Date]) AS WeekdayNumber
FROM DateSeries;
GO

CREATE VIEW analytics.dim_customer AS
SELECT 
    c.CustomerID,
    c.PersonID,
    c.StoreID,
    CASE 
        WHEN c.PersonID IS NOT NULL THEN 'Person'
        WHEN c.StoreID IS NOT NULL THEN 'Store'
        ELSE 'Unknown'
    END AS CustomerType,
    CASE    
        WHEN c.PersonID IS NOT NULL THEN CONCAT(p.FirstName, ' ', p.LastName)
        WHEN c.StoreID IS NOT NULL THEN s.Name
        ELSE 'Unknown Customer'
    END AS CustomerName, 
    c.AccountNumber,
    c.TerritoryID,
    st.Name AS TerritoryName,
    st.[Group] AS TerritoryGroup
FROM Sales.Customer c
LEFT JOIN Person.Person p 
    ON c.PersonID = p.BusinessEntityID
LEFT JOIN Sales.Store s 
    ON c.StoreID = s.BusinessEntityID
LEFT JOIN Sales.SalesTerritory st 
    ON c.TerritoryID = st.TerritoryID;
GO