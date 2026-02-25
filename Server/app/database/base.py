from sqlalchemy.orm import declarative_base
from sqlalchemy import Column, Boolean, DateTime, event

Base = declarative_base()


class SoftDeleteMixin:
    is_deleted = Column(Boolean, default=False, index=True)
    deleted_at = Column(DateTime, nullable=True)


# Global listener handles soft-delete filtering for all models that
# subclass SoftDeleteMixin.  We avoid per-class event attachment which
# can fail if the target type doesn't support the event (see earlier
# InvalidRequestError). Listening on ``Query`` lets us examine the
# entities involved and transparently add the ``is_deleted`` clause.
#
# If a query involves multiple tables we only add the filter for those
# entities that inherit the mixin.  ``retval=True`` ensures the modified
# query is returned so SQLAlchemy uses our augmented version.

from sqlalchemy.orm import Query

@event.listens_for(Query, 'before_compile', retval=True)
def _soft_delete_before_compile(query):
    # ``column_descriptions`` is available on ORM Query objects and
    # lists dictionaries with an ``entity`` key when the query is
    # against mapped classes.  We inspect each entity and, if it is a
    # subclass of SoftDeleteMixin, append the filter.
    if not hasattr(query, 'column_descriptions'):
        return query
    for desc in query.column_descriptions:
        entity = desc.get('entity')
        if entity is not None and isinstance(entity, type) and issubclass(entity, SoftDeleteMixin):
            # ``enable_assertions(False)`` silences warnings when we
            # modify the query after it has been constructed.
            query = query.enable_assertions(False).filter(entity.is_deleted == False)
    return query
 