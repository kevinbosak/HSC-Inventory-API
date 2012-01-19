package HSC::Schema::User;

use base qw/DBIx::Class::Core/;

__PACKAGE__->table('user');
__PACKAGE__->add_columns(
            'username' => { data_type => "VARCHAR", is_nullable => 0, size => 100 },
            'password_hash' => { data_type => 'CHAR', size => 100 },
            'c_time' => {data_type => 'TIMESTAMP', is_nullable => 0, default_value => \'CURRENT_TIMESTAMP'},
            'm_time' => {data_type => 'DATETIME', is_nullable => 1},
);
__PACKAGE__->set_primary_key('username');

1;
