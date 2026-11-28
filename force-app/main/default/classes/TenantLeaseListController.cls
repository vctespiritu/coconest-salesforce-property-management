public with sharing class TenantLeaseListController {
    
    @AuraEnabled(cacheable=true)
    public static List<Tenant_Lease_Association__c> getLeasesByTenantId(Id tenantId){

        if(tenantId == null){
            return new List<Tenant_Lease_Association__c>();
        }

        try {
            return TenantLeaseAssociationSelector.getLeasesByTenantId(new List<Id>{ tenantId });

        } catch (CocoNestExceptions.AccessException e) {
            throw new AuraHandledException(e.getMessage());

        } catch (NoAccessException e) {
            throw new AuraHandledException(
                'You do not have permission to retrieve lease information.'
            );

        } catch (QueryException e) {
            System.debug(LoggingLevel.ERROR, e.getStackTraceString());
            throw new AuraHandledException(
                'An error occurred while retrieving lease information.'
            );
        }

    }

}