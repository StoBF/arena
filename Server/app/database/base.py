from sqlalchemy.orm import declarative_base
from sqlalchemy import Column, Boolean, DateTime, event

Base = declarative_base()


class SoftDeleteMixin:
    is_deleted = Column(Boolean, default=False, index=True)
    deleted_at = Column(DateTime, nullable=True)

    @classmethod
    def __declare_last__(cls):
        # Append default WHERE clause to queries targeting this class.
        # Automatically filters out soft-deleted rows without repeating
        # the condition in every query. See project-architecture notes.
        def _before_compile(query):
            if hasattr(query, '_where_criteria'):
                entities = [desc.get('entity') for desc in query.column_descriptions]
                if cls in entities:
                    query._where_criteria += (cls.is_deleted == False,)
        event.listen(cls, 'before_compile', _before_compile)
 