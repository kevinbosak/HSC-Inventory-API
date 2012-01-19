package hsc_inventory;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Data::Validate::MySQL qw(is_int is_date is_boolean is_varchar is_text is_enum);
use Digest::SHA qw(sha256_hex);
use MIME::Base64 qw(encode_base64url);

our $VERSION = '0.1';

#prefix '/hsc_inventory';
set serializer => 'JSON';

get '/' => sub {
    my $schema = schema('hsc_inventory');
    template 'index';
};

get '/item/:item_id' => sub {
    my $schema = schema('hsc_inventory');
    template 'item';
};

before sub {
    # check auth token
    my $token = params->{token};

    return if request->method eq 'GET' || request->path eq '/api/get_token';

    my $schema = schema('hsc_inventory');
    my $token_obj = $schema->resultset('Token')->single({token => $token, expire_time => {'>' => \'now()'}}) if $token;

    if (!$token_obj) {
        # TODO: use 403 if the user is logged in but not allowed to access a resource
        status 401;
        halt {error => 'This request requires a valid token'};
    }
};

prefix '/api';

# takes usersname/pass and returns a token (and expiration info?)
post '/get_token' => sub {
    my $username = params->{username};
    my $pass = params->{password};

    # check for username/hashed pass
    if ($username && $pass) {
        my $schema = schema('hsc_inventory');
        my $password_hash = sha256_hex(config->{password_salt} . $pass),
        my $user = $schema->resultset('User')->find($username);
        if ($user && $user->password_hash eq $password_hash) {
            my $rand = int(rand(time)*100);
            my $token = encode_base64url($username . $rand);
            my $expire = config->{token_expire};
            $schema->resultset('Token')->create({token => $token, expire_time => \"date_add(now(), INTERVAL $expire DAY)"});
            return {token => $token};
        }
    }

    return {error => 'Invalid username/password'};
};

any ['get', 'put', 'options'] => '/get_token' => sub {
    status 405;
};

# list all items
get '/items' => sub {
    my $schema = schema('hsc_inventory');

    my $offset = params->{offset} || 0;
    debug("OFFSET: $offset");

    # FIXME: validate sort field
    my $sort_by = params->{sort_by} || 'name';

    # TODO: allow user to specify columns returned?

    my @rows = $schema->resultset('Inventory')->search({}, {
            rows => 20,
            offset => $offset,
            sort_by => $sort_by,
            result_class => 'DBIx::Class::ResultClass::HashRefInflator',
        })->all;

    my $total = $schema->resultset('Inventory')->search({}, {
            sort_by => $sort_by,
        })->count;

    return {total => $total, data => \@rows};
};

# creates a new item and returns its ID
# FIXME: Location header should contain the URL for the newly created item
post '/items' => sub {
    my $schema = schema('hsc_inventory');

    my $columns = $schema->source('Inventory')->columns_info;
    my @errors = ();

    my $create_params = {};
    for my $col (keys %$columns) {
        next if ($col eq 'c_time' || $col eq 'm_time' || $col eq 'inventory_id');

        my $col_meta = $columns->{$col};
        if (!$col_meta->{is_nullable} && (! defined params->{$col} || params->{$col} eq '')) {
            if (! defined $col_meta->{default_value}) {
                push @errors, "Missing required field: '$col'";
            }
            next;
        }

        # nullify the field if possible
        if ($col_meta->{is_nullable} && params->{$col} eq '') {
            $create_params->{$col} = undef;
            next;
        }

        next unless defined params->{$col};

        my $result;
        if ($col_meta->{data_type} eq 'DATE') {
            $result = is_date(params->{$col});

        } elsif ($col_meta->{data_type} eq 'INT') {
            $result = is_int(params->{$col});

        } elsif ($col_meta->{data_type} eq 'BOOL') {
            $result = is_boolean(params->{$col});

        } elsif ($col_meta->{data_type} eq 'ENUM') {
            $result = is_enum(params->{$col}, @{$col_meta->{extra}->{list}});

        } else {

            if ($col_meta->{size}) {
                $result = is_varchar(params->{$col}, $col_meta->{size});
                
            } else {
                $result = is_text(params->{$col});
            }
        }

        if (! defined $result) {
            push @errors, "$col contains invalid data";
        } else {
            $create_params->{$col} = params->{$col};
        }
    }


    if (@errors) {
        return {errors => \@errors};
    }

    my $item = $schema->resultset('Inventory')->create($create_params) or die "Could not create inventory";
    my $id = $item->inventory_id;

    return {item_id => $id};
};

any ['put', 'options'] => '/items' => sub {
    status 405;
};

# returns a hashref of field names as keys and field type/size
get '/items/fields' => sub {
    my $columns = schema('hsc_inventory')->source('Inventory')->columns_info;
    my $return = {};

    for my $col (keys %$columns) { 
        my $col_meta = $columns->{$col};

        if ($col_meta->{data_type} eq 'DATE') {
            $return->{$col} = {type => 'date'};

        } elsif ($col_meta->{data_type} eq 'INT') {
            $return->{$col} = {type => 'int'};

        } elsif ($col_meta->{data_type} eq 'BOOL') {
            $return->{$col} = {type => 'flag'};

        } elsif ($col_meta->{data_type} eq 'ENUM') {
            $return->{$col} = {type => 'list', values => $col_meta->{extra}->{list}};

        } else {
            $return->{$col} = {type => 'text', size => $col_meta->{size} ? $col_meta->{size} : 0};
        }

        $return->{$col}->{pretty_name} = join(' ', map(ucfirst, map(lc, split('_', $col))));
        $return->{$col}->{pretty_name} = 'Modified' if ($col eq 'm_time');
        $return->{$col}->{pretty_name} = 'Created' if ($col eq 'c_time');

        $return->{$col}->{required} = $col_meta->{is_nullable} ? 0 : 1;
        $return->{$col}->{not_editable} = 1 if $col eq 'c_time' || $col eq 'm_time' || $col eq 'inventory_id';
    }
    return $return;
};

# gets item info based given an ID
get '/items/:item_id' => sub {
    my $id = params->{item_id};

    return {error => 'Must specify an item_id'} unless $id;

    my $schema = schema('hsc_inventory');
    my $item = $schema->resultset('Inventory')->find($id, {result_class => 'DBIx::Class::ResultClass::HashRefInflator'});

    status 201;
    return $item if $item;

    status 'not_found';
    return "Item '$id' not found";
};

# updates an item's info given the info and an ID
put '/items/:item_id' => sub {
    my $id = params->{item_id};
    return {error => 'No item_id specified'} unless $id;

    # TODO: some sort of auth check on which cols a user can edit?
    #    maybe some users can only check in/out items, others can edit details
    my $schema = schema('hsc_inventory');

    my $item = $schema->resultset('Inventory')->find($id);
    return {error => "Invalid item ID: $id"} unless $item;

    my $columns = $schema->source('Inventory')->columns_info;
    my @errors = ();

    my $update_params = {};
    my $params = params;
    for my $col (keys %$params) {
        next if ($col eq 'c_time' || $col eq 'm_time' || $col eq 'item_id');

        my $col_meta = $columns->{$col};
        next unless defined $col_meta;

        # nullify the field if possible
        if ($col_meta->{is_nullable} && params->{$col} eq '') {
            $update_params->{$col} = undef;
            next;
        }

        my $result;
        if ($col_meta->{data_type} eq 'DATE') {
            $result = is_date(params->{$col});

        } elsif ($col_meta->{data_type} eq 'INT') {
            $result = is_int(params->{$col});

        } elsif ($col_meta->{data_type} eq 'BOOL') {
            $result = is_boolean(params->{$col});

        } elsif ($col_meta->{data_type} eq 'ENUM') {
            $result = is_enum(params->{$col}, @{$col_meta->{extra}->{list}});

        } else {

            if ($col_meta->{size}) {
                $result = is_varchar(params->{$col}, $col_meta->{size});
                
            } else {
                $result = is_text(params->{$col});
            }
        }

        if (! defined $result) {
            push @errors, "$col contains invalid data";
        } else {
            $update_params->{$col} = params->{$col};
        }
    }
    
    if (@errors) {
        return {errors => \@errors};
    }

    $item->update($update_params) or die "Could not update item";
    return {item_id => $id};
};

del '/items/:item_id' => sub {
    my $id = params->{item_id};
    return {error => 'No item_id specified'} unless $id;

    my $schema = schema('hsc_inventory');

    my $item = $schema->resultset('Inventory')->find($id);
    return {error => "Invalid item ID: $id"} unless $item;

    $item->delete() or die "Could not delete item";
    return {success => 1};
};

# FIXME: add OPTIONS routes to show available interactions for resources (in Allow header)
# body can contain details

true;
