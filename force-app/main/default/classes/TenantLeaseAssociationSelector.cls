/**
 * Description: To handle Tenant_Lease_Association__c queries
 * @author Victor Espiritu 
 */
public with sharing class TenantLeaseAssociationSelector {


    /**
     * Description: gets all the Tenant Lease Associations of the passed in leaseIds
     * @param leaseIds the passed in lease ids to get all the tenant lease associations of it
     * @return list of tenant lease associations.
     */
    public static List<Tenant_Lease_Association__c> getTenantLeaseAssocByLeaseId(List<Id> leaseIds){

        return [
                SELECT
                    Id,
                    Lease__c,
                    Tenant__c,
                    Is_Primary_Tenant__c,
                    Occupant_Type__c
                FROM
                    Tenant_Lease_Association__c
                WHERE
                    Lease__c IN : leaseIds
            ];

    }

    /**
     * Description: Retrieves lease associations for the provided
     * tenant IDs while enforcing read permissions.
     * @param tenantIds The tenant record IDs.
     * @return List of accessible tenant lease associations.
     */
    public static List<Tenant_Lease_Association__c> getLeasesByTenantId(List<Id> tenantIds){

        if( !Tenant_Lease_Association__c.SObjectType.getDescribe().IsAccessible() ||
            !Tenant_Lease_Association__c.Tenant__c.getDescribe().IsAccessible()){
            throw new CocoNestExceptions.AccessException(
                'You do not have permission to retrieve tenant lease associations.'
            );
        }
        
        List<Tenant_Lease_Association__c> records =  [
            SELECT
                Id,
                Lease__c,
                Lease__r.Name, 
                Lease__r.Property__c,
                Lease__r.Property__r.Name,
                Lease__r.Status__c, 
                Lease__r.Start_Date__c, 
                Lease__r.End_Date__c, 
                Lease__r.Monthly_Rent__c, 
                Is_Primary_Tenant__c, 
                Occupant_Type__c  
            FROM 
                Tenant_Lease_Association__c 
            WHERE 
                Tenant__c IN :tenantIds
            WITH SYSTEM_MODE
        ];

        SObjectAccessDecision decision = Security.stripInaccessible(AccessType.READABLE, records);

        return (List<Tenant_Lease_Association__c>) decision.getRecords();

    }

}