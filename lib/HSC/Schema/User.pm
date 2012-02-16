package HSC::Schema::User;

use base qw/DBIx::Class::Core/;

__PACKAGE__->table('user');
__PACKAGE__->add_columns(
            'user_id' => {data_type => 'INT UNSIGNED', is_auto_increment => 1, is_nullable => 0},
            'username' => { data_type => "VARCHAR", is_nullable => 0, size => 100 },
            'password_hash' => { data_type => 'CHAR', size => 100 },
            'c_time' => {data_type => 'TIMESTAMP', is_nullable => 0, default_value => \'CURRENT_TIMESTAMP'},
            'm_time' => {data_type => 'DATETIME', is_nullable => 1},
);
__PACKAGE__->set_primary_key('user_id');
__PACKAGE__->add_unique_constraint(['username']);
__PACKAGE__->has_many(tokens => 'HSC::Schema::Token', 'user_id');

1;
