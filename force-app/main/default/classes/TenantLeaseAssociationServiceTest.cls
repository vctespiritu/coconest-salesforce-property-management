/**
 * Description: Integration tests for Tenant_Lease_Association__c business logic.
 * Tests use DML so the full Trigger -> Dispatcher -> Handler -> Service -> Selector
 * execution path is validated.
 * @author Victor Espiritu
 */
@IsTest(SeeAllData=false)
private class TenantLeaseAssociationServiceTest {

    @TestSetup
    static void makeData() {

        List<Account> testAccounts = testUtils.CreateAccounts(1, 'Property Owner');
        insert testAccounts;

        List<Property__c> properties = testUtils.CreateProperties(1, testAccounts[0]);
        insert properties;

        List<Lease__c> leases = testUtils.CreateLeases(1, properties[0]);
        insert leases;

        List<Tenant__c> tenants = testUtils.CreateTenants(1);
        insert tenants;
    }

    @IsTest
    static void testInsertWithoutPrimaryFails() {

        Lease__c lease = [SELECT Id FROM Lease__c LIMIT 1];
        Tenant__c tenant = [SELECT Id FROM Tenant__c LIMIT 1];

        Tenant_Lease_Association__c tla = new Tenant_Lease_Association__c(
            Lease__c = lease.Id,
            Tenant__c = tenant.Id,
            Occupant_Type__c = 'Tenant',
            Is_Primary_Tenant__c = false
        );

        Test.startTest();
        Database.SaveResult result = Database.insert(tla, false);
        Test.stopTest();

        Assert.isFalse(result.isSuccess(), 'A lease must have a primary tenant.');
        Assert.isTrue(
            result.getErrors()[0].getMessage().contains(TenantLeaseAssociationConstant.PRIMARY_TENANT_ERROR),
            'The error should explain why the insert was rejected.'
        );

        Integer associationCount = [
            SELECT COUNT()
            FROM Tenant_Lease_Association__c
            WHERE Lease__c = :lease.Id
        ];

        Assert.areEqual(
            0,
            associationCount,
            'The invalid Tenant Lease Association should not be inserted.'
        );
    }

    @IsTest
    static void testInsertPrimarySucceeds() {

        Lease__c lease = [SELECT Id FROM Lease__c LIMIT 1];
        Tenant__c tenant = [SELECT Id FROM Tenant__c LIMIT 1];

        Tenant_Lease_Association__c tla = new Tenant_Lease_Association__c(
            Lease__c = lease.Id,
            Tenant__c = tenant.Id,
            Occupant_Type__c = 'Tenant',
            Is_Primary_Tenant__c = true
        );

        Test.startTest();
        Database.SaveResult result = Database.insert(tla, false);
        Test.stopTest();

        Assert.isTrue(result.isSuccess(), 'Inserting a primary TLA should succeed.');

        Tenant_Lease_Association__c insertedTla = [
            SELECT Id, Lease__c, Tenant__c, Is_Primary_Tenant__c
            FROM Tenant_Lease_Association__c
            WHERE Id = :tla.Id
        ];

        Assert.isTrue(
            insertedTla.Is_Primary_Tenant__c,
            'The association should be inserted as the primary tenant.'
        );

        Lease__c updatedLease = [
            SELECT Id, Primary_Tenant__c
            FROM Lease__c
            WHERE Id = :lease.Id
        ];

        Assert.areEqual(
            tenant.Id,
            updatedLease.Primary_Tenant__c,
            'The primary tenant Flow should synchronize the Lease primary tenant.'
        );
    }

    @IsTest
    static void testInsertNonPrimaryWhenLeaseHasPrimarySucceeds() {

        Lease__c lease = [SELECT Id FROM Lease__c LIMIT 1];
        Tenant__c primaryTenant = [SELECT Id FROM Tenant__c LIMIT 1];

        List<Tenant__c> additionalTenants = testUtils.CreateTenants(1);
        insert additionalTenants;

        Tenant_Lease_Association__c primaryTla = new Tenant_Lease_Association__c(
            Lease__c = lease.Id,
            Tenant__c = primaryTenant.Id,
            Occupant_Type__c = 'Tenant',
            Is_Primary_Tenant__c = true
        );
        insert primaryTla;

        Tenant_Lease_Association__c secondaryTla = new Tenant_Lease_Association__c(
            Lease__c = lease.Id,
            Tenant__c = additionalTenants[0].Id,
            Occupant_Type__c = 'Co-Tenant',
            Is_Primary_Tenant__c = false
        );

        Test.startTest();
        Database.SaveResult result = Database.insert(secondaryTla, false);
        Test.stopTest();

        Assert.isTrue(result.isSuccess(), 'Inserting a non-primary TLA should succeed when the lease has a primary.');

        Integer associationCount = [
            SELECT COUNT()
            FROM Tenant_Lease_Association__c
            WHERE Lease__c = :lease.Id
        ];

        Assert.areEqual(
            2,
            associationCount,
            'A non-primary tenant should be allowed when the lease already has a primary tenant.'
        );
    }

    @IsTest
    static void testRemovingOnlyPrimaryFails() {

        Lease__c lease = [SELECT Id FROM Lease__c LIMIT 1];
        Tenant__c tenant = [SELECT Id FROM Tenant__c LIMIT 1];

        Tenant_Lease_Association__c primaryTla = new Tenant_Lease_Association__c(
            Lease__c = lease.Id,
            Tenant__c = tenant.Id,
            Occupant_Type__c = 'Tenant',
            Is_Primary_Tenant__c = true
        );
        insert primaryTla;

        primaryTla.Is_Primary_Tenant__c = false;

        Test.startTest();
        Database.SaveResult result = Database.update(primaryTla, false);
        Test.stopTest();

        Assert.isFalse(result.isSuccess(), 'Removing the only primary must fail.');
        Assert.isTrue(
            result.getErrors()[0].getMessage().contains(TenantLeaseAssociationConstant.PRIMARY_TENANT_ERROR),
            'The error should explain why removing the last primary was rejected.'
        );

        Tenant_Lease_Association__c persistedTla = [
            SELECT Is_Primary_Tenant__c
            FROM Tenant_Lease_Association__c
            WHERE Id = :primaryTla.Id
        ];

        Assert.isTrue(
            persistedTla.Is_Primary_Tenant__c,
            'The failed update should leave the persisted association as primary.'
        );
    }

    @IsTest
    static void testBulkUpdateErrorsOnlyOnOffendingPrimary() {

        Lease__c lease = [SELECT Id FROM Lease__c LIMIT 1];
        Tenant__c primaryTenant = [SELECT Id FROM Tenant__c LIMIT 1];

        List<Tenant__c> additionalTenants = testUtils.CreateTenants(2);
        insert additionalTenants;

        List<Tenant_Lease_Association__c> tlas = new List<Tenant_Lease_Association__c>{
            new Tenant_Lease_Association__c(
                Lease__c = lease.Id,
                Tenant__c = primaryTenant.Id,
                Occupant_Type__c = 'Tenant',
                Is_Primary_Tenant__c = true
            ),
            new Tenant_Lease_Association__c(
                Lease__c = lease.Id,
                Tenant__c = additionalTenants[0].Id,
                Occupant_Type__c = 'Co-Tenant',
                Is_Primary_Tenant__c = false
            ),
            new Tenant_Lease_Association__c(
                Lease__c = lease.Id,
                Tenant__c = additionalTenants[1].Id,
                Occupant_Type__c = 'Co-Tenant',
                Is_Primary_Tenant__c = false
            )
        };
        insert tlas;

        tlas[0].Is_Primary_Tenant__c = false;
        tlas[1].Notes__c = 'Unrelated update 1';
        tlas[2].Notes__c = 'Unrelated update 2';

        Test.startTest();
        Database.SaveResult[] results = Database.update(tlas, false);
        Test.stopTest();

        Assert.areEqual(3, results.size(), 'Each TLA should return a DML result.');
        Assert.isFalse(results[0].isSuccess(), 'Removing the sole primary must fail.');
        Assert.isTrue(
            results[0].getErrors()[0].getMessage().contains(TenantLeaseAssociationConstant.PRIMARY_TENANT_ERROR),
            'Only the offending primary TLA should receive the expected validation message.'
        );
        Assert.isTrue(results[1].isSuccess(), 'The first unrelated update should succeed.');
        Assert.isTrue(results[2].isSuccess(), 'The second unrelated update should succeed.');

        Set<Id> tlaIds = new Map<Id, Tenant_Lease_Association__c>(tlas).keySet();
        Map<Id, Tenant_Lease_Association__c> persistedTlas =
            new Map<Id, Tenant_Lease_Association__c>([
                SELECT Id, Is_Primary_Tenant__c, Notes__c
                FROM Tenant_Lease_Association__c
                WHERE Id IN :tlaIds
            ]);

        Assert.isTrue(
            persistedTlas.get(tlas[0].Id).Is_Primary_Tenant__c,
            'The rejected update must preserve the existing primary.'
        );
        Assert.areEqual(
            'Unrelated update 1', persistedTlas.get(tlas[1].Id).Notes__c,
            'The first unrelated change should persist.'
        );
        Assert.areEqual(
            'Unrelated update 2', persistedTlas.get(tlas[2].Id).Notes__c,
            'The second unrelated change should persist.'
        );
    }

    @IsTest
    static void testPrimaryHandoffSucceedsInSameTransaction() {

        Lease__c lease = [SELECT Id FROM Lease__c LIMIT 1];
        Tenant__c firstTenant = [SELECT Id FROM Tenant__c LIMIT 1];

        List<Tenant__c> additionalTenants = testUtils.CreateTenants(1);
        insert additionalTenants;

        Tenant_Lease_Association__c firstTla = new Tenant_Lease_Association__c(
            Lease__c = lease.Id,
            Tenant__c = firstTenant.Id,
            Occupant_Type__c = 'Tenant',
            Is_Primary_Tenant__c = true
        );
        insert firstTla;

        Tenant_Lease_Association__c secondTla = new Tenant_Lease_Association__c(
            Lease__c = lease.Id,
            Tenant__c = additionalTenants[0].Id,
            Occupant_Type__c = 'Co-Tenant',
            Is_Primary_Tenant__c = false
        );
        insert secondTla;

        firstTla.Is_Primary_Tenant__c = false;
        secondTla.Is_Primary_Tenant__c = true;

        Test.startTest();
        Database.SaveResult[] results = Database.update(new List<Tenant_Lease_Association__c>{ firstTla, secondTla }, false);
        Test.stopTest();

        for (Database.SaveResult result : results) {
            Assert.isTrue(result.isSuccess(), 'Both records in a primary handoff should succeed.');
        }

        Map<Id, Tenant_Lease_Association__c> associationsById =
            new Map<Id, Tenant_Lease_Association__c>([
                SELECT Id, Tenant__c, Is_Primary_Tenant__c
                FROM Tenant_Lease_Association__c
                WHERE Id IN :new Set<Id>{ firstTla.Id, secondTla.Id }
            ]);

        Assert.isFalse(
            associationsById.get(firstTla.Id).Is_Primary_Tenant__c,
            'The original primary tenant should no longer be primary.'
        );
        Assert.isTrue(
            associationsById.get(secondTla.Id).Is_Primary_Tenant__c,
            'The new primary tenant should be saved successfully.'
        );

        Lease__c updatedLease = [
            SELECT Primary_Tenant__c
            FROM Lease__c
            WHERE Id = :lease.Id
        ];

        Assert.areEqual(
            additionalTenants[0].Id,
            updatedLease.Primary_Tenant__c,
            'The Lease should point to the new primary tenant after the handoff.'
        );
    }

    @IsTest
    static void testReplacePrimaryInReverseOrder(){

        Lease__c lease = [SELECT Id FROM Lease__c LIMIT 1];
        Tenant__c firstTenant = [SELECT Id FROM Tenant__c LIMIT 1];

        List<Tenant__c> additionalTenants = testUtils.CreateTenants(1);
        insert additionalTenants;

        Tenant_Lease_Association__c firstTla = new Tenant_Lease_Association__c(
            Lease__c = lease.Id,
            Tenant__c = firstTenant.Id,
            Occupant_Type__c = 'Tenant',
            Is_Primary_Tenant__c = true
        );
        insert firstTla;

        Tenant_Lease_Association__c secondTla = new Tenant_Lease_Association__c(
            Lease__c = lease.Id,
            Tenant__c = additionalTenants[0].Id,
            Occupant_Type__c = 'Co-Tenant',
            Is_Primary_Tenant__c = false
        );
        insert secondTla;

        firstTla.Is_Primary_Tenant__c = false;
        secondTla.Is_Primary_Tenant__c = true;

        Test.startTest();
        Database.SaveResult[] results = Database.update(new List<Tenant_Lease_Association__c>{ secondTla, firstTla }, false);
        Test.stopTest();

        for (Database.SaveResult result : results) {
            Assert.isTrue(result.isSuccess(), 'Both records should succeed regardless of DML order.');
        }

        Map<Id, Tenant_Lease_Association__c> associationsById =
            new Map<Id, Tenant_Lease_Association__c>([
                SELECT Id, Tenant__c, Is_Primary_Tenant__c
                FROM Tenant_Lease_Association__c
                WHERE Id IN :new Set<Id>{ firstTla.Id, secondTla.Id }
            ]);

        Assert.isFalse(
            associationsById.get(firstTla.Id).Is_Primary_Tenant__c,
            'The original primary tenant should no longer be primary.'
        );
        Assert.isTrue(
            associationsById.get(secondTla.Id).Is_Primary_Tenant__c,
            'The new primary tenant should be saved successfully.'
        );

        Lease__c updatedLease = [
            SELECT Primary_Tenant__c
            FROM Lease__c
            WHERE Id = :lease.Id
        ];

        Assert.areEqual(
            additionalTenants[0].Id,
            updatedLease.Primary_Tenant__c,
            'The Lease should point to the new primary tenant after the handoff.'
        );
    }

    @IsTest
    static void testDeleteSolePrimaryFails(){

        Lease__c lease = [SELECT Id FROM Lease__c LIMIT 1];

        Tenant__c tenant = [SELECT Id FROM Tenant__c LIMIT 1];

        Tenant_Lease_Association__c tla = new Tenant_Lease_Association__c(
            Lease__c = lease.Id,
            Tenant__c = tenant.Id,
            Occupant_Type__c = 'Tenant',
            Is_Primary_Tenant__c = true
        );

        insert tla;

        Test.startTest();
        Database.DeleteResult result = Database.delete(tla, false);
        Test.stopTest();

        Assert.isFalse(result.isSuccess(), 'Deleting the only primary must fail.');
        Assert.isTrue(
            result.getErrors()[0].getMessage().contains(TenantLeaseAssociationConstant.PRIMARY_TENANT_ERROR),
            'The error should explain why deleting the last primary was rejected.'
        );

        Tenant_Lease_Association__c persistedTla = [
            SELECT Is_Primary_Tenant__c
            FROM Tenant_Lease_Association__c
            WHERE Id = :tla.Id
        ];

        Assert.isTrue(
            persistedTla.Is_Primary_Tenant__c,
            'The failed delete should leave the persisted association as primary.'
        );
    }

    @IsTest
    static void testDeleteNonPrimarySucceeds(){

        Lease__c lease = [SELECT Id FROM Lease__c LIMIT 1];

        Tenant__c primaryTenant = [SELECT Id FROM Tenant__c LIMIT 1];

        List<Tenant__c> nonPrimaryTenant = testUtils.CreateTenants(1);
        insert nonPrimaryTenant;

        Tenant_Lease_Association__c primaryTla = new Tenant_Lease_Association__c(
            Lease__c = lease.Id,
            Tenant__c = primaryTenant.Id,
            Occupant_Type__c = 'Tenant',
            Is_Primary_Tenant__c = true
        );

        Tenant_Lease_Association__c nonPrimaryTla = new Tenant_Lease_Association__c(
            Lease__c = lease.Id,
            Tenant__c = nonPrimaryTenant[0].Id,
            Occupant_Type__c = 'Co-Tenant',
            Is_Primary_Tenant__c = false
        );


        insert new List<Tenant_Lease_Association__c>{ primaryTla, nonPrimaryTla };

        Test.startTest();
        Database.DeleteResult result = Database.delete(nonPrimaryTla, false);
        Test.stopTest();

        Assert.isTrue(result.isSuccess(), 'Deleting a non-primary TLA should succeed.');

        List<Tenant_Lease_Association__c> leaseTlas = [
            SELECT Id, Is_Primary_Tenant__c
            FROM Tenant_Lease_Association__c
            WHERE Lease__c = :lease.Id
        ];

        Assert.areEqual(1, leaseTlas.size(), 'A non-primary association can be deleted when a primary is present.');
        Assert.isTrue(leaseTlas[0].Is_Primary_Tenant__c, 'The only association left should be a primary.');
    }

    @IsTest
    static void testDeletingOneOfMultiplePrimariesSucceeds(){

        Lease__c lease = [SELECT Id FROM Lease__c LIMIT 1];

        Tenant__c primaryTenant = [SELECT Id FROM Tenant__c LIMIT 1];

        List<Tenant__c> secondPrimaryTenant = testUtils.CreateTenants(1);
        insert secondPrimaryTenant;

        Tenant_Lease_Association__c primaryTla = new Tenant_Lease_Association__c(
            Lease__c = lease.Id,
            Tenant__c = primaryTenant.Id,
            Occupant_Type__c = 'Tenant',
            Is_Primary_Tenant__c = true
        );

        Tenant_Lease_Association__c secondPrimaryTla = new Tenant_Lease_Association__c(
            Lease__c = lease.Id,
            Tenant__c = secondPrimaryTenant[0].Id,
            Occupant_Type__c = 'Tenant',
            Is_Primary_Tenant__c = true
        );


        insert new List<Tenant_Lease_Association__c>{ primaryTla, secondPrimaryTla };

        Test.startTest();
        Database.DeleteResult result = Database.delete(secondPrimaryTla, false);
        Test.stopTest();

        Assert.isTrue(result.isSuccess(), 'Deleting one of multiple primaries should succeed.');

        List<Tenant_Lease_Association__c> leaseTlas = [
            SELECT Id, Is_Primary_Tenant__c
            FROM Tenant_Lease_Association__c
            WHERE Lease__c = :lease.Id
        ];

        Assert.areEqual(1, leaseTlas.size(), 'A non-primary association can be deleted when a primary is present.');
        Assert.isTrue(leaseTlas[0].Is_Primary_Tenant__c, 'The only association left should be a primary.');
    }

    @IsTest
    static void testDeletingAllPrimariesFromSameLeaseFails(){

        Lease__c lease = [SELECT Id FROM Lease__c LIMIT 1];

        Tenant__c primaryTenant = [SELECT Id FROM Tenant__c LIMIT 1];

        List<Tenant__c> secondPrimaryTenant = testUtils.CreateTenants(1);
        insert secondPrimaryTenant;

        List<Tenant_Lease_Association__c> tlas = new List<Tenant_Lease_Association__c>();

        tlas.add(
            new Tenant_Lease_Association__c(
                Lease__c = lease.Id,
                Tenant__c = primaryTenant.Id,
                Occupant_Type__c = 'Tenant',
                Is_Primary_Tenant__c = true
            )
        );

        tlas.add(
            new Tenant_Lease_Association__c(
                Lease__c = lease.Id,
                Tenant__c = secondPrimaryTenant[0].Id,
                Occupant_Type__c = 'Tenant',
                Is_Primary_Tenant__c = true
            )
        );

        insert tlas;

        Test.startTest();
        Database.DeleteResult[] results = Database.delete(tlas, false);
        Test.stopTest();

        Assert.areEqual(tlas.size(), results.size(), 'Each record should have a DML result.');
        for (Database.DeleteResult result : results) {
            Assert.isFalse(result.isSuccess(), 'Deleting all primary TLAs must fail.');
            Assert.isTrue(
                result.getErrors()[0].getMessage().contains(TenantLeaseAssociationConstant.PRIMARY_TENANT_ERROR),
                'The error should identify the last-primary violation.'
            );
        }
        Integer remainingPrimaries = [
            SELECT COUNT()
            FROM Tenant_Lease_Association__c
            WHERE Lease__c = :lease.Id AND Is_Primary_Tenant__c = true
        ];
        Assert.areEqual(2, remainingPrimaries, 'Both primary TLAs should remain after rejected deletes.');
    }

    @IsTest
    static void testUpdatingUnrelatedFieldsToPrimarySucceeds(){

        Lease__c lease = [SELECT Id FROM Lease__c LIMIT 1];

        Tenant__c tenant = [SELECT Id FROM Tenant__c LIMIT 1];

        Tenant_Lease_Association__c tla = new Tenant_Lease_Association__c(
            Lease__c = lease.Id,
            Tenant__c = tenant.Id,
            Occupant_Type__c = 'Tenant',
            Is_Primary_Tenant__c = true
        );

        insert tla;

        tla.Occupant_Type__c = 'Co-Tenant';

        Test.startTest();
        Database.SaveResult result = Database.update(tla, false);
        Test.stopTest();

        Assert.isTrue(result.isSuccess(), 'Updating an unrelated field on a primary TLA should succeed.');

        Tenant_Lease_Association__c persistedTla = [
            SELECT Occupant_Type__c, Is_Primary_Tenant__c
            FROM Tenant_Lease_Association__c
            WHERE Id = :tla.Id
        ];
        Assert.areEqual('Co-Tenant', persistedTla.Occupant_Type__c);
        Assert.isTrue(persistedTla.Is_Primary_Tenant__c);
    }

    @IsTest
    static void testUpdatingUnrelatedFieldsToNonPrimarySucceeds(){

        Lease__c lease = [SELECT Id FROM Lease__c LIMIT 1];

        Tenant__c primaryTenant = [SELECT Id FROM Tenant__c LIMIT 1];

        List<Tenant__c> secondPrimaryTenant = testUtils.CreateTenants(1);
        insert secondPrimaryTenant;

        List<Tenant_Lease_Association__c> tlas = new List<Tenant_Lease_Association__c>();

        tlas.add(
            new Tenant_Lease_Association__c(
                Lease__c = lease.Id,
                Tenant__c = primaryTenant.Id,
                Occupant_Type__c = 'Tenant',
                Is_Primary_Tenant__c = true
            )
        );

        tlas.add(
            new Tenant_Lease_Association__c(
                Lease__c = lease.Id,
                Tenant__c = secondPrimaryTenant[0].Id,
                Occupant_Type__c = 'Co-Tenant',
                Is_Primary_Tenant__c = false
            )
        );

        insert tlas;

        tlas[1].Notes__c = 'Test';

        Test.startTest();
        Database.SaveResult result = Database.update(tlas[1], false);
        Test.stopTest();

        Assert.isTrue(result.isSuccess(), 'Updating an unrelated field on a non-primary TLA should succeed.');

        Id nonPrimaryTlaId = tlas[1].Id;
        Tenant_Lease_Association__c persistedTla = [
            SELECT Notes__c, Is_Primary_Tenant__c
            FROM Tenant_Lease_Association__c
            WHERE Id = :nonPrimaryTlaId
        ];
        Assert.areEqual('Test', persistedTla.Notes__c);
        Assert.isFalse(persistedTla.Is_Primary_Tenant__c);
    }

    @IsTest
    static void testBulkInsert200PrimaryAssociationsSucceeds() {

        Property__c property = [SELECT Id FROM Property__c LIMIT 1];

        List<Lease__c> leases = testUtils.CreateLeases(TenantLeaseAssociationConstant.BULK_SIZE, property);
        insert leases;

        List<Tenant__c> tenants = testUtils.CreateTenants(TenantLeaseAssociationConstant.BULK_SIZE);
        insert tenants;

        List<Tenant_Lease_Association__c> associations =
            new List<Tenant_Lease_Association__c>();

        for (Integer i = 0; i < TenantLeaseAssociationConstant.BULK_SIZE; i++) {
            associations.add(
                new Tenant_Lease_Association__c(
                    Lease__c = leases[i].Id,
                    Tenant__c = tenants[i].Id,
                    Occupant_Type__c = 'Tenant',
                    Is_Primary_Tenant__c = true
                )
            );
        }

        Test.startTest();
        Database.SaveResult[] results = Database.insert(associations, false);
        Test.stopTest();

        for (Database.SaveResult result : results) {
            Assert.isTrue(result.isSuccess(), 'All 200 primary TLA inserts should succeed.');
        }

        Set<Id> leaseIds = new Map<Id, Lease__c>(leases).keySet();

        Integer associationCount = [
            SELECT COUNT()
            FROM Tenant_Lease_Association__c
            WHERE Lease__c IN :leaseIds
        ];

        Assert.areEqual(
            TenantLeaseAssociationConstant.BULK_SIZE,
            associationCount,
            'All 200 valid primary tenant associations should be inserted in one transaction.'
        );

        Integer leasesWithPrimaryTenant = [
            SELECT COUNT()
            FROM Lease__c
            WHERE Id IN :leaseIds
            AND Primary_Tenant__c != null
        ];

        Assert.areEqual(
            TenantLeaseAssociationConstant.BULK_SIZE,
            leasesWithPrimaryTenant,
            'The primary tenant Flow should synchronize all leases in the bulk transaction.'
        );
    }

    @IsTest
    static void testBulkInsert200AssociationsWithoutPrimariesFails() {

        Property__c property = [SELECT Id FROM Property__c LIMIT 1];

        List<Lease__c> leases = testUtils.CreateLeases(TenantLeaseAssociationConstant.BULK_SIZE, property);
        insert leases;

        List<Tenant__c> tenants = testUtils.CreateTenants(TenantLeaseAssociationConstant.BULK_SIZE);
        insert tenants;

        List<Tenant_Lease_Association__c> associations =
            new List<Tenant_Lease_Association__c>();

        for (Integer i = 0; i < TenantLeaseAssociationConstant.BULK_SIZE; i++) {
            associations.add(
                new Tenant_Lease_Association__c(
                    Lease__c = leases[i].Id,
                    Tenant__c = tenants[i].Id,
                    Occupant_Type__c = 'Tenant',
                    Is_Primary_Tenant__c = false
                )
            );
        }

        Test.startTest();
        Database.SaveResult[] results = Database.insert(associations, false);
        Test.stopTest();

        Assert.areEqual(associations.size(), results.size(), 'Each record should have a DML result.');
        for (Database.SaveResult result : results) {
            Assert.isFalse(result.isSuccess(), 'An initial non-primary association must fail.');
            Assert.isTrue(
                result.getErrors()[0].getMessage().contains(TenantLeaseAssociationConstant.PRIMARY_TENANT_ERROR),
                'Every invalid insert should have the expected validation error.'
            );
        }

        Set<Id> leaseIds = new Map<Id, Lease__c>(leases).keySet();

        Integer associationCount = [
            SELECT COUNT()
            FROM Tenant_Lease_Association__c
            WHERE Lease__c IN :leaseIds
        ];

        Assert.areEqual(
            0,
            associationCount,
            'The failed bulk insert should not persist any associations.'
        );
    }

    @IsTest
    static void testBulkUpdateRemoving200PrimariesFails() {

        Property__c property = [SELECT Id FROM Property__c LIMIT 1];

        List<Lease__c> leases = testUtils.CreateLeases(TenantLeaseAssociationConstant.BULK_SIZE, property);
        insert leases;

        List<Tenant__c> tenants = testUtils.CreateTenants(TenantLeaseAssociationConstant.BULK_SIZE);
        insert tenants;

        List<Tenant_Lease_Association__c> associations =
            new List<Tenant_Lease_Association__c>();

        for (Integer i = 0; i < TenantLeaseAssociationConstant.BULK_SIZE; i++) {
            associations.add(
                new Tenant_Lease_Association__c(
                    Lease__c = leases[i].Id,
                    Tenant__c = tenants[i].Id,
                    Occupant_Type__c = 'Tenant',
                    Is_Primary_Tenant__c = true
                )
            );
        }

        insert associations;

        for (Tenant_Lease_Association__c association : associations) {
            association.Is_Primary_Tenant__c = false;
        }

        Test.startTest();
        Database.SaveResult[] results = Database.update(associations, false);
        Test.stopTest();

        Assert.areEqual(associations.size(), results.size(), 'Each record should have a DML result.');
        for (Database.SaveResult result : results) {
            Assert.isFalse(result.isSuccess(), 'Removing a lease\'s sole primary must fail.');
            Assert.isTrue(
                result.getErrors()[0].getMessage().contains(TenantLeaseAssociationConstant.PRIMARY_TENANT_ERROR),
                'Every invalid update should have the expected validation error.'
            );
        }

        Set<Id> associationIds =
            new Map<Id, Tenant_Lease_Association__c>(associations).keySet();

        Integer persistedPrimaryCount = [
            SELECT COUNT()
            FROM Tenant_Lease_Association__c
            WHERE Id IN :associationIds
            AND Is_Primary_Tenant__c = true
        ];

        Assert.areEqual(
            TenantLeaseAssociationConstant.BULK_SIZE,
            persistedPrimaryCount,
            'The failed bulk update should leave all persisted associations as primary.'
        );
    }

    @IsTest
    static void testBulkDelete200SolePrimariesFails(){

        Property__c property = [SELECT Id FROM Property__c LIMIT 1];

        List<Lease__c> leases = testUtils.CreateLeases(TenantLeaseAssociationConstant.BULK_SIZE, property);
        insert leases;

        List<Tenant__c> tenants = testUtils.CreateTenants(TenantLeaseAssociationConstant.BULK_SIZE);
        insert tenants;

        List<Tenant_Lease_Association__c> associations = new List<Tenant_Lease_Association__c>();

        for (Integer i = 0; i < TenantLeaseAssociationConstant.BULK_SIZE; i++) {
            associations.add(
                new Tenant_Lease_Association__c(
                    Lease__c = leases[i].Id,
                    Tenant__c = tenants[i].Id,
                    Occupant_Type__c = 'Tenant',
                    Is_Primary_Tenant__c = true
                )
            );
        }

        insert associations;

        Test.startTest();
        Database.DeleteResult[] results = Database.delete(associations, false);
        Test.stopTest();

        Assert.areEqual(associations.size(), results.size(), 'Each record should have a DML result.');
        for (Database.DeleteResult result : results) {
            Assert.isFalse(result.isSuccess(), 'Deleting a lease\'s sole primary must fail.');
            Assert.isTrue(
                result.getErrors()[0].getMessage().contains(TenantLeaseAssociationConstant.PRIMARY_TENANT_ERROR),
                'Every invalid delete should have the expected validation error.'
            );
        }

        Set<Id> associationIds = new Map<Id, Tenant_Lease_Association__c>(associations).keySet();

        Integer countOfAssociations = [
            SELECT COUNT()
            FROM Tenant_Lease_Association__c
            WHERE Id IN :associationIds
            AND Is_Primary_Tenant__c = true 
        ];

        Assert.areEqual(TenantLeaseAssociationConstant.BULK_SIZE, countOfAssociations, 
            'Bulk deleting 200 sole primaries should not be allowed.');
    }

    @IsTest
    static void testBulkDelete200NonPrimariesSucceeds(){

        Property__c property = [SELECT Id FROM Property__c LIMIT 1];

        List<Lease__c> leases = testUtils.CreateLeases(TenantLeaseAssociationConstant.BULK_SIZE, property);
        insert leases;

        List<Tenant__c> tenants = testUtils.CreateTenants(TenantLeaseAssociationConstant.BULK_SIZE);
        insert tenants;

        List<Tenant_Lease_Association__c> primaryAssociations = new List<Tenant_Lease_Association__c>();

        for (Integer i = 0; i < TenantLeaseAssociationConstant.BULK_SIZE; i++) {
            primaryAssociations.add(
                new Tenant_Lease_Association__c(
                    Lease__c = leases[i].Id,
                    Tenant__c = tenants[i].Id,
                    Occupant_Type__c = 'Tenant',
                    Is_Primary_Tenant__c = true
                )
            );
        }

        insert primaryAssociations;

        List<Tenant__c> nonPrimaryTenants = testUtils.CreateTenants(TenantLeaseAssociationConstant.BULK_SIZE);
        insert nonPrimaryTenants;

        List<Tenant_Lease_Association__c> nonPrimaryAssociations = new List<Tenant_Lease_Association__c>();

        for (Integer i = 0; i < TenantLeaseAssociationConstant.BULK_SIZE; i++) {
            nonPrimaryAssociations.add(
                new Tenant_Lease_Association__c(
                    Lease__c = leases[i].Id,
                    Tenant__c = nonPrimaryTenants[i].Id,
                    Occupant_Type__c = 'Co-Tenant',
                    Is_Primary_Tenant__c = false
                )
            );
        }

        insert nonPrimaryAssociations;

        Test.startTest();
        Database.DeleteResult[] results = Database.delete(nonPrimaryAssociations, false);
        Test.stopTest();

        for (Database.DeleteResult result : results) {
            Assert.isTrue(result.isSuccess(), 'Deleting non-primary TLAs should succeed for all 200 leases.');
        }

        Set<Id> associationIds = new Map<Id, Tenant_Lease_Association__c>(nonPrimaryAssociations).keySet();

        Integer countOfAssociations = [
            SELECT COUNT()
            FROM Tenant_Lease_Association__c
            WHERE Id IN :associationIds
            AND Is_Primary_Tenant__c = false 
        ];

        Assert.areEqual(0, countOfAssociations, 
            'Bulk deleting 200 non-primaries should be allowed.');
    }

    
    @IsTest
    static void testBulkPrimaryHandoffSucceeds() {

        Property__c property = [SELECT Id FROM Property__c LIMIT 1];

        Integer leaseCount = TenantLeaseAssociationConstant.BULK_SIZE / 2;

        List<Lease__c> leases = testUtils.CreateLeases(leaseCount, property);
        insert leases;

        List<Tenant__c> tenants = testUtils.CreateTenants(
            TenantLeaseAssociationConstant.BULK_SIZE
        );
        insert tenants;

        List<Tenant_Lease_Association__c> primaryTlas =
            new List<Tenant_Lease_Association__c>();

        List<Tenant_Lease_Association__c> secondaryTlas =
            new List<Tenant_Lease_Association__c>();

        Map<Id, Id> expectedPrimaryTenantByLeaseId = new Map<Id, Id>();

        for (Integer i = 0; i < leaseCount; i++) {

            primaryTlas.add(new Tenant_Lease_Association__c(
                Lease__c = leases[i].Id,
                Tenant__c = tenants[i].Id,
                Occupant_Type__c = 'Tenant',
                Is_Primary_Tenant__c = true
            ));

            secondaryTlas.add(new Tenant_Lease_Association__c(
                Lease__c = leases[i].Id,
                Tenant__c = tenants[i + leaseCount].Id,
                Occupant_Type__c = 'Co-Tenant',
                Is_Primary_Tenant__c = false
            ));

            expectedPrimaryTenantByLeaseId.put(
                leases[i].Id,
                tenants[i + leaseCount].Id
            );
        }

        insert primaryTlas;
        insert secondaryTlas;

        List<Tenant_Lease_Association__c> associationsToUpdate =
            new List<Tenant_Lease_Association__c>();

        for (Integer i = 0; i < leaseCount; i++) {

            primaryTlas[i].Is_Primary_Tenant__c = false;
            secondaryTlas[i].Is_Primary_Tenant__c = true;

            associationsToUpdate.add(primaryTlas[i]);
            associationsToUpdate.add(secondaryTlas[i]);
        }

        Test.startTest();
        Database.SaveResult[] results = Database.update(associationsToUpdate, false);
        Test.stopTest();

        for (Database.SaveResult result : results) {
            Assert.isTrue(result.isSuccess(), 'All 200 primary handoff updates should succeed.');
        }

        Set<Id> leaseIds = new Map<Id, Lease__c>(leases).keySet();

        Map<Id, Integer> primaryCountByLeaseId = new Map<Id, Integer>();

        for (Tenant_Lease_Association__c tla : [
            SELECT Id, Lease__c, Tenant__c, Is_Primary_Tenant__c
            FROM Tenant_Lease_Association__c
            WHERE Lease__c IN :leaseIds
        ]) {

            if (tla.Is_Primary_Tenant__c) {

                Integer count = primaryCountByLeaseId.containsKey(tla.Lease__c)
                    ? primaryCountByLeaseId.get(tla.Lease__c)
                    : 0;

                primaryCountByLeaseId.put(tla.Lease__c, count + 1);

                Assert.areEqual(
                    expectedPrimaryTenantByLeaseId.get(tla.Lease__c),
                    tla.Tenant__c,
                    'The replacement tenant should be the new primary.'
                );
            }
        }

        for (Lease__c lease : [
            SELECT Id, Primary_Tenant__c
            FROM Lease__c
            WHERE Id IN :leaseIds
        ]) {

            Assert.areEqual(
                1,
                primaryCountByLeaseId.get(lease.Id),
                'Each lease should retain exactly one primary tenant.'
            );

            Assert.areEqual(
                expectedPrimaryTenantByLeaseId.get(lease.Id),
                lease.Primary_Tenant__c,
                'The Lease primary tenant should be synchronized.'
            );
        }
    }

}