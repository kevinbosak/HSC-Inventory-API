package HSC::Schema::Token;

use base qw/DBIx::Class::Core/;

__PACKAGE__->table('token');
__PACKAGE__->add_columns(
            'token' => { data_type => "VARCHAR", is_nullable => 0, size => 100 },
            'password_hash' => { data_type => 'VARCHAR', size => 100 },
            'expire_time' => {data_type => 'DATETIME', is_nullable => 1 },
            'c_time' => {data_type => 'TIMESTAMP', is_nullable => 0, default_value => \'CURRENT_TIMESTAMP'},
            'm_time' => {data_type => 'DATETIME', is_nullable => 1},
);
__PACKAGE__->set_primary_key('token');

1;
