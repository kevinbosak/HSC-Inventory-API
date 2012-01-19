package HSC::Schema::Inventory;

use base qw/DBIx::Class::Core/;

__PACKAGE__->table('inventory');
__PACKAGE__->add_columns(
            'inventory_id' => {data_type => 'INT UNSIGNED', is_auto_increment => 1, is_nullable => 0},
            'name' => { data_type => "VARCHAR", is_nullable => 0, size => 100 },
            'description' => {data_type => 'TEXT', is_nullable => 1},
            'location' => {data_type => 'VARCHAR', is_nullable => 1, size => 255},
            'is_consumable' => {data_type => 'BOOL', default_value => 0, is_nullable => 0},
            'ownership_status' => {data_type => 'ENUM', default_value => 'permanent', extra => {list => ['permanent', 'loan']}},
            'ownership_description' => {data_type => 'VARCHAR', is_nullable => 1, size => 255},
            'is_loanable' => {data_type => 'BOOL', default_value => 1, is_nullable => 0},
            'on_loan_to' => {data_type => 'VARCHAR', size => 255, is_nullable => 1},
            'expected_return_date' => {data_type => 'DATE', is_nullable => 1},
            'notes' => {data_type => 'TEXT', is_nullable => 1},
            'date_acquired' => {data_type => 'DATE', is_nullable => 1},
            'original_value' => {data_type => 'DECIMAL(10,7)', is_nullable => 1},
            'c_time' => {data_type => 'TIMESTAMP', is_nullable => 0, default_value => \'CURRENT_TIMESTAMP'},
            'm_time' => {data_type => 'DATETIME', is_nullable => 1},
);
__PACKAGE__->set_primary_key('inventory_id');

sub sqlt_deploy_hook {
    my ($self, $sqlt_table) = @_;
    $sqlt_table->options({charset => 'utf8', engine => 'myisam'}),
    $sqlt_table->add_index(
            name => 'name_description_notes',
            fields => ['name', 'description', 'notes'],
            type => 'fulltext',
    );
}

1;
