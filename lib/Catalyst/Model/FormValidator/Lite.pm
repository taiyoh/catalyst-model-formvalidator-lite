package Catalyst::Model::FormValidator::Lite;

use strict;
use warnings;
use Scalar::Util qw/blessed refaddr/;
use base qw/Catalyst::Model/;
__PACKAGE__->mk_classdata('validator_profile');
__PACKAGE__->validator_profile({});

our $VERSION = '0.001_2';

use FormValidator::Lite;
use YAML;

sub new {
    my $self = shift;
    $self = $self->next::method(@_);
    my ($c) = @_;
    my $conf = $c->config->{validator};
    my $data = do {
        $conf->{profile} ||= '';
        if ( -f $conf->{profile} ) {
            no warnings 'once';
            $c->log->debug("Loaded FV::Lite Profile \"$conf->{profile}\"") if $c->debug;
            local $YAML::UseAliases = 0;
            my $yml = YAML::Dump( YAML::LoadFile( $conf->{profile} ) );
            utf8::decode($yml);
            YAML::Load($yml);    # XXX: remove yaml aliases
        }
        else {
            {};
        }
    };
    $self->_form_action($data->{$_}, $_) for keys %$data;
    my $constraints = $conf->{constraints};
    $constraints = [$constraints] unless ref $constraints;
    FormValidator::Lite->load_constraints(@$constraints);
    $self;
}

sub ACCEPT_CONTEXT {
    my $self = shift;
    my ($c) = @_;

    return $self->build_per_context_instance(@_) unless ref $c;
    my $key = blessed $self ? refaddr $self : $self;
    return $c->stash->{"__InstancePerContext_${key}"} ||= $self->build_per_context_instance(@_);
}

sub build_per_context_instance {
    my $self  = shift;
    my $c     = shift;
    my $form = {};
    my $action = $c->action->reverse;
    $form = $self->validator_profile->{ $action }
        if exists $self->validator_profile->{ $action };
    my $klass = 'Catalyst::Model::FormValidator::Lite::PerRequest';
    my $rule = $_[1] ? +{ @_ } : $_[0];
    $rule ||= {};
    $rule = +{ @$rule } if ref $rule eq 'ARRAY';
    return $klass->new( $c->req, $form, $rule );
}

sub _form_action {
    my ( $self, $prof, $action ) = @_;
    my $cache;
    for my $n ( keys %$prof ) {
        for my $r ( @{ $prof->{$n} } ) {
            my $rule;
            if ( $rule = $r->{rule} ) {
                if ( ref $rule eq 'ARRAY' ) {
                    push @{ $cache->{rule}->{$n} }, $rule;
                    $rule = $rule->[0];
                }
                else {
                    push @{ $cache->{rule}->{$n} }, $rule;
                }
            }
            else {
                $rule = $r->{self_rule};
            }
            $rule = lc($rule);
            $cache->{message}->{"${n}.${rule}"} = $r->{message} if $rule;
        }
    }
    $self->validator_profile->{$action} = $cache;
}


package Catalyst::Model::FormValidator::Lite::PerRequest;
use Clone qw/clone/;

use Data::Dumper qw/Dumper/;
sub new {
    my $pkg = shift;
    my ( $req, $form, $rule ) = @_;
    my $validator = FormValidator::Lite->new($req);
    my $self = bless {
        _validator => $validator,
        _rule      => {},
        _message   => {},
    }, $pkg;
    $self->_merge_rule(clone($form), $rule);
    $self->{_validator}->set_message( $self->{_message} );
    $self->{_validator}->check( %{ $self->{_rule} } );
    $self;
}

sub _merge_rule {
    my ( $self, $cache, $rule ) = @_;
    $self->{_rule}    = $cache->{rule} || {};
    $self->{_message} = $cache->{message} || {};
    $rule ||= {};
    if (ref $rule && ref $rule eq 'HASH') {
        while ( my ( $n, $r ) = each %$rule ) {
            push @{ $self->{_rule}->{$n} }, $r;
        }
    }
}

sub AUTOLOAD {
    my $self = shift;
    (my $method) = (our $AUTOLOAD =~ /([^:]+)$/);
    return if $method eq "DESTROY";

    $self->{_validator}->$method(@_) if $self->{_validator}->can($method);
}

1;
