import { LightningElement, wire, api } from 'lwc';
import FORM_FACTOR from '@salesforce/client/formFactor';
import getLeases from '@salesforce/apex/TenantLeaseListController.getLeasesByTenantId';

const COLUMNS = [
    { label: 'Lease', fieldName: 'leaseUrl', type: 'url', typeAttributes: { label: { fieldName: 'Name' }, target: '_self' } },
    { label: 'Property', fieldName: 'propertyUrl', type:'url', typeAttributes: { label: { fieldName: 'PropertyName' }, target: '_self' } },
    { label: 'Status', fieldName: 'Status__c' },
    { label: 'Start Date', fieldName: 'Start_Date__c', type: 'date-local' },
    { label: 'End Date', fieldName: 'End_Date__c', type: 'date-local' },
    { label: 'Rent', fieldName: 'Monthly_Rent__c', type: 'currency' },
    { label: 'Is Primary', fieldName: 'Is_Primary_Tenant__c' },
    { label: 'Occupant Type', fieldName: 'Occupant_Type__c' },
];

export default class TenantLeaseList extends LightningElement {

    @api recordId;

    leases = [];
    columns = COLUMNS;
    error;
    isLoading = true;

    get isDesktop(){
        return FORM_FACTOR === 'Large';
    }

    @wire(getLeases, { tenantId: '$recordId' })
    wiredLeases({ data, error }){

        if(data) {
            this.leases = data.map(record => ({
                Id: record.Id,
                Name: record.Lease__r?.Name,
                leaseUrl: record.Lease__c 
                    ? `/lightning/r/Lease__c/${record.Lease__c}/view`
                    : null,
                PropertyName: record.Lease__r?.Property__r?.Name ?? '', 
                propertyUrl: record.Lease__r?.Property__c 
                    ?`/lightning/r/Property__c/${record.Lease__r.Property__c}/view`
                    : null,
                Status__c: record.Lease__r?.Status__c,
                Start_Date__c: record.Lease__r?.Start_Date__c,
                End_Date__c: record.Lease__r?.End_Date__c,
                Monthly_Rent__c: record.Lease__r?.Monthly_Rent__c,
                Is_Primary_Tenant__c: record.Is_Primary_Tenant__c === undefined || record.Is_Primary_Tenant__c === null
                    ? 'N/A' : record.Is_Primary_Tenant__c ? 'Yes' : 'No',
                Occupant_Type__c: record.Occupant_Type__c
            }));

            this.error = undefined;
            this.isLoading = false;

        } else if(error){
            this.error = error;
            this.leases = [];
            this.isLoading = false;
        }
    }

    get hasLeases(){
        return this.leases.length > 0;
    }

    get errorMessage(){
        return this.error ? 'Unable to load lease information.' : null;
    }

}